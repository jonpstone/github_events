class GithubEvent < ApplicationRecord
  has_one :push_event, dependent: :destroy

  validates :event_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :raw_payload, presence: true

  scope :by_type, ->(type) { where(event_type: type) }
  scope :recent, -> { order(github_created_at: :desc) }
  scope :since, ->(datetime) { where("github_created_at > ?", datetime) }

  after_create :create_push_event_and_queue_enrichment

  def self.from_github_api(event_data)
    return nil if event_data.blank?
    
    find_or_create_by(event_id: event_data['id']) do |record|
      record.event_type = event_data['type']
      record.actor_login = event_data.dig('actor', 'login')
      record.actor_avatar_url = event_data.dig('actor', 'avatar_url')
      record.repo_name = event_data.dig('repo', 'name')
      record.repo_id = event_data.dig('repo', 'id')
      record.raw_payload = event_data.dup
      record.payload = event_data['payload'].presence || {}
      record.github_created_at = event_data['created_at']
    end
  end

  def raw_payload_pretty
    JSON.pretty_generate(raw_payload)
  end

  private

  def create_push_event_and_queue_enrichment
    if event_type == 'PushEvent'
      PushEvent.create_from_github_event(self)
      EnrichPushEventsJob.perform_async(1)
    end
  end
end