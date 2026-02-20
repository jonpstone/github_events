class EnrichPushEventsJob
  include Sidekiq::Job

  sidekiq_options retry: 5, dead: true

  def perform(batch_size = 50)
    unenriched_events = PushEvent.where(enriched_at: nil).limit(batch_size)

    if unenriched_events.empty?
      Rails.logger.info("No unenriched push events to process")
      return { success: true, enriched_count: 0, failed_count: 0 }
    end

    service = EnrichPushEventService.new
    results = service.enrich_batch(unenriched_events)

    successful = results.count { |r| r[:result][:success] }
    failed = results.count { |r| !r[:result][:success] }

    Rails.logger.info("Enriched #{successful} push events, #{failed} failed")

    { success: true, enriched_count: successful, failed_count: failed }
  rescue EnrichPushEventService::RateLimitError => e
    Rails.logger.warn("Rate limited, will retry later: #{e.message}")
    raise e
  rescue => e
    Rails.logger.error("Failed to enrich push events: #{e.message}")
    raise e
  end
end