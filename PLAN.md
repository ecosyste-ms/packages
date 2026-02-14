## Change package status from NULL to 'active'

Problem: the composite index on (status, last_synced_at) is useless because status IS NULL matches nearly all 13M rows. Also, check_status never updates last_synced_at when the ecosystem returns nil and status is already nil, causing packages to stay permanently "outdated" and waste sync slots.

The migration needs to happen safely on a running system with the API staying stable between deploys. Scopes must never use OR conditions against 13M rows.

### Phase 1: Reader override + check_status fix (deploy now)

No scope changes, no migration. Just two changes to package.rb:

- Add reader override so API returns nil when db value is 'active'
- Fix check_status to write 'active' instead of nil, and always update last_synced_at

This is safe because scopes still use `where(status: nil)`. Packages that get check_status called will flip to 'active' in the db but the reader hides it from the API. Those packages drop out of the `active` scope until the backfill + scope change in phase 3.

That's acceptable because check_status only runs on packages that are already failing to sync. Them dropping out of `active` temporarily is fine, and it stops them from clogging the sync queue (which is the whole point).

### Phase 2: Backfill NULL -> 'active' (running now)

```ruby
loop do
  ids = []
  Package.where(status: nil).limit(5000).select(:id).each_instance do |p|
    ids << p.id
    if ids.size == 100
      Package.where(id: ids).update_all(status: 'active')
      ids = []
      print '.'
    end
  end
  Package.where(id: ids).update_all(status: 'active') if ids.any?
  puts
end
```

### Phase 3: Scope changes + column default (deploy after backfill)

Once all rows are 'active', switch everything in one deploy:

**db/migrate/xxx_set_default_status_on_packages.rb**
```ruby
change_column_default :packages, :status, from: nil, to: 'active'
```

**app/models/package.rb**
- `scope :active` -> `where(status: 'active')`
- `scope :inactive` -> `where.not(status: 'active')`

**app/models/version.rb**
- `scope :active` -> `where(status: 'active')`

**app/models/registry.rb:293-294**
- `packages.where(status: nil)` -> `packages.where(status: 'active')`

**app/controllers/top_controller.rb:9**
- `status is null` -> `status = 'active'`
