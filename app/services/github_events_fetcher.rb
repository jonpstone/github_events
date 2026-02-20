class GithubEventsFetcher
  require 'net/http'
  require 'json'

  BASE_URL = 'https://api.github.com/events'
  
  def self.fetch_and_store(per_page: 30)
    new.fetch_and_store(per_page)
  end

  def fetch_and_store(per_page = 30)
    last_fetch = Rails.cache.read('github:last_fetch_time')
    if last_fetch && (Time.current - last_fetch) < 2.minutes
      Rails.logger.info("Skipping fetch - fetched #{(Time.current - last_fetch).to_i}s ago")
      return { success: true, skipped: true }
    end
    
    uri = URI("#{BASE_URL}?per_page=#{per_page}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'GithubEventsApp'
    response = http.request(request)

    if response.code == '200'
      events = JSON.parse(response.body)
      events = events.select { |event| event["type"] == "PushEvent"}
      created_count = 0
      
      events.each do |event|
        if event.present?
          result = GithubEvent.from_github_api(event)
          created_count += 1 if result.previously_new_record?
        end
      end
      
      {
        success: true,
        total_events: events.count,
        newly_created: created_count,
        api_response_code: response.code
      }
    else
      {
        success: false,
        error: response.body,
        api_response_code: response.code
      }
    end
  rescue => e
    {
      success: false,
      error: e.message,
      backtrace: e.backtrace.first(5)
    }
  end

  Rails.cache.write('github:last_fetch_time', Time.current, expires_in: 5.minutes)
end