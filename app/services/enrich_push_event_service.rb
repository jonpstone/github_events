class EnrichPushEventService
  require 'net/http'
  require 'json'

  CACHE_DURATION = 24.hours
  REQUEST_TIMEOUT = 5
  MAX_RETRIES = 3

  class FetchError < StandardError; end
  class RateLimitError < StandardError; end

  def enrich(push_event)
    return { success: true, message: 'Already enriched' } if push_event.enriched_at.present?

    github_event = push_event.github_event
    raw_payload = github_event.raw_payload

    actor_data = raw_payload['actor']
    repo_data = raw_payload['repo']

    actor = enrich_actor(actor_data)
    repository = enrich_repository(repo_data)

    push_event.update!(
      actor: actor,
      repository: repository,
      enriched_at: Time.current
    )

    {
      success: true,
      enriched_actor: actor.present?,
      enriched_repository: repository.present?
    }
  rescue RateLimitError => e
    Rails.logger.warn("Rate limited during enrichment: #{e.message}")
    { success: false, error: 'Rate limited', retry_after: 3600 }
  rescue => e
    Rails.logger.error("Error enriching push event #{push_event.id}: #{e.message}")
    { success: false, error: e.message }
  end

  def enrich_batch(push_events)
    results = []
    push_events.each do |event|
      result = enrich(event)
      results << { event_id: event.id, result: result }
    end
    results
  end

  private

  def enrich_actor(actor_data)
    return nil if actor_data.blank?

    actor = ::Actor.find_or_create_from_payload(actor_data)
    return actor unless actor.should_enrich?

    fetch_and_update_actor(actor, actor_data['url'])
    actor
  rescue => e
    Rails.logger.warn("Could not enrich actor: #{e.message}")
    actor
  end

  def enrich_repository(repo_data)
    return nil if repo_data.blank?

    repository = ::Repository.find_or_create_from_payload(repo_data)
    return repository unless repository.should_enrich?

    fetch_and_update_repository(repository, repo_data['url'])
    repository
  rescue => e
    Rails.logger.warn("Could not enrich repository: #{e.message}")
    repository
  end

  def fetch_and_update_actor(actor, api_url)
    return unless api_url.present?

    data = fetch_from_url(api_url)
    return unless data

    actor.mark_enriched(
      name: data['name'],
      bio: data['bio'],
      company: data['company'],
      location: data['location'],
      followers: data['followers'],
      following: data['following'],
      public_repos: data['public_repos']
    )
  rescue RateLimitError
    raise
  rescue => e
    Rails.logger.warn("Could not fetch actor from #{api_url}: #{e.message}")
    actor.mark_failed
  end

  def fetch_and_update_repository(repository, api_url)
    return unless api_url.present?

    data = fetch_from_url(api_url)
    return unless data

    repository.mark_enriched(
      description: data['description'],
      stars_count: data['stargazers_count'],
      forks_count: data['forks_count'],
      watchers_count: data['watchers_count'],
      language: data['language'],
      homepage: data['homepage'],
      topics: data['topics'],
      is_fork: data['fork'],
      is_private: data['private'],
      license: data.dig('license', 'name')
    )
  rescue RateLimitError
    raise
  rescue => e
    Rails.logger.warn("Could not fetch repository from #{api_url}: #{e.message}")
    repository.mark_failed
  end

  def fetch_from_url(url, retry_count = 0)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'GithubEventsApp/1.0'
    request['Accept'] = 'application/vnd.github.v3+json'

    response = http.request(request)

    case response.code.to_i
    when 200
      JSON.parse(response.body)
    when 429
      raise RateLimitError, "Rate limited: #{response['X-RateLimit-Reset']}"
    when 404
      Rails.logger.warn("Resource not found: #{url}")
      nil
    when 500..599
      if retry_count < MAX_RETRIES
        sleep(2 ** retry_count)
        fetch_from_url(url, retry_count + 1)
      else
        raise FetchError, "Server error after #{MAX_RETRIES} retries"
      end
    else
      raise FetchError, "HTTP #{response.code}: #{response.body}"
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    if retry_count < MAX_RETRIES
      sleep(2 ** retry_count)
      fetch_from_url(url, retry_count + 1)
    else
      raise FetchError, "Timeout after #{MAX_RETRIES} retries"
    end
  rescue JSON::ParserError => e
    raise FetchError, "Invalid JSON response: #{e.message}"
  end
end