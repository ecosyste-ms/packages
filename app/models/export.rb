class Export < ApplicationRecord
  validates_presence_of :date, :bucket_name, :packages_count

  def download_url
    "https://#{bucket_name}.s3.amazonaws.com/packages-#{date}.tar.gz"
  end
end
