class FetchGithubEventsJob
  include Sidekiq::Job

  sidekiq_options retry: 5, dead: true

  def perform
    result = GithubEventsFetcher.fetch_and_store
    
    if result[:success]
      Rails.logger.info("✓ Fetched #{result[:newly_created]} new push events")
    else
      Rails.logger.error("✗ Failed to fetch events: #{result[:error]}")
      raise result[:error]
    end
  end
end