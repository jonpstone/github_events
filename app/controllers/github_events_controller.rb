class GithubEventsController < ApplicationController
  def index
    @events = GithubEvent.recent.page(params[:page]).per(20)
  end

  def fetch
    result = GithubEventsFetcher.fetch_and_store(per_page: 30)
    
    if result[:success]
      redirect_to github_events_path, notice: "Fetched #{result[:count] || result[:total_events]} events"
    elsif result[:rate_limited]
      reset_time = result[:reset_time]
      minutes_until = reset_time ? ((reset_time - Time.current) / 60).ceil : 1
      
      redirect_to github_events_path, alert: 
        "Rate limit reached. API will reset in #{minutes_until} minute(s). " \
        "Enrichment will resume automatically."
    else
      redirect_to github_events_path, alert: "Error: #{result[:error]}"
    end
  end

  def api_index
    @events = GithubEvent.recent.limit(50)
    render json: @events
  end

  def rate_limit_status
    # curl http://localhost:3000/github_events/rate_limit_status | jq
    remaining = Rails.cache.read('github:rate_limit:remaining') || 60
    limit = Rails.cache.read('github:rate_limit:limit') || 60
    reset_timestamp = Rails.cache.read('github:rate_limit:reset')
    
    percentage_used = ((limit - remaining).to_f / limit) * 100
    minutes_until_reset = reset_timestamp ? ((reset_timestamp - Time.current.to_i) / 60).ceil : nil
    
    status = case percentage_used
             when 0..70 then 'healthy'
             when 70..90 then 'warning'
             else 'critical'
             end
    
    render json: {
      remaining: remaining,
      limit: limit,
      percentage_used: percentage_used.round(1),
      status: status,
      resets_in_minutes: minutes_until_reset,
      resets_at: reset_timestamp ? Time.at(reset_timestamp) : nil,
      unenriched_count: PushEvent.unenriched.count,
      orphaned_count: PushEvent.orphaned.count,
      dead_letter_count: fetch_dead_letter_count,
      total_events: PushEvent.count,
      timestamp: Time.current
    }
  end

  private

  def fetch_dead_letter_count
    begin
      Sidekiq::DeadSet.new.size
    rescue => e
      Rails.logger.warn("Could not fetch dead letter count: #{e.message}")
      0
    end
  end
end