class UserAgentStats
  def self.last_30_days
    stats = Hash.new(0)
    
    # Get data for the last 30 days
    30.times do |i|
      date = i.days.ago.to_date.to_s
      day_key = "api_requests:#{date}"
      
      # Get all user agents and their counts for this day
      day_stats = REDIS.zrevrange(day_key, 0, -1, with_scores: true)
      
      # Aggregate counts
      day_stats.each do |user_agent, count|
        stats[user_agent] += count.to_i
      end
    end
    
    # Sort by count descending
    stats.sort_by { |_, count| -count }.to_h
  end
  
  def self.by_day
    results = {}
    
    30.times do |i|
      date = i.days.ago.to_date
      date_str = date.to_s
      day_key = "api_requests:#{date_str}"
      
      day_stats = REDIS.zrevrange(day_key, 0, -1, with_scores: true)
      
      if day_stats.any?
        results[date_str] = day_stats.map { |agent, count| 
          { user_agent: agent, count: count.to_i }
        }
      end
    end
    
    results
  end
end