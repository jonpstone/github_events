class EnrichPushEventsJob
  include Sidekiq::Job

  sidekiq_options retry: 5, dead: true

  def perform(batch_size = 50)
    unenriched = PushEvent.unenriched.limit(batch_size)
    unenriched.each_with_index do |event, index|
      sleep(0.1) if index > 0
      
      EnrichPushEventService.new.enrich(event)
    rescue GithubRateLimitTracker::RateLimitExceeded => e
      Rails.logger.warn("Rate limit hit after #{index} enrichments")
      break
    end

    start_time = Time.current
    orphaned = PushEvent.orphaned.count
    Rails.logger.warn("⚠️ #{orphaned} push events without repositories") if orphaned > 0

    unenriched_count = PushEvent.unenriched.count
    dead_letter_count = Sidekiq::DeadSet.new.size
    
    if dead_letter_count > 0
      Rails.logger.error("🚨 Dead letter queue has #{dead_letter_count} jobs")
    end

    unenriched_events = PushEvent.unenriched.limit(batch_size)

    if unenriched_events.empty?
      Rails.logger.info("✓ No unenriched push events to process")
      return { success: true, enriched_count: 0, failed_count: 0 }
    end

    service = EnrichPushEventService.new
    results = service.enrich_batch(unenriched_events)

    successful = results.count { |r| r[:result][:success] }
    failed = results.count { |r| !r[:result][:success] }
    rate_limited = results.count { |r| r[:result][:error] == 'Rate limited' }

    elapsed = Time.current - start_time

    log_metrics({
      event: 'enrich_push_events_completed',
      processed: successful + failed,
      successful: successful,
      failed: failed,
      rate_limited: rate_limited,
      elapsed_seconds: elapsed.round(2),
      queue_depth: unenriched_count - successful - failed,
      dead_letter_queue: dead_letter_count
    })

    { success: true, enriched_count: successful, failed_count: failed }
  rescue GithubRateLimitTracker::RateLimitExceeded => e
    Rails.logger.warn({
      event: 'enrich_rate_limit_exceeded',
      error: e.message,
      will_retry_in_seconds: 3600
    }.to_json)
    raise e
  rescue => e
    Rails.logger.error({
      event: 'enrich_push_events_failed',
      error: e.message,
      backtrace: e.backtrace.first(5)
    }.to_json)
    raise e
  end

  private

  def log_metrics(metrics)
    Rails.logger.info(metrics.to_json)
  end
end