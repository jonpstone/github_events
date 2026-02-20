class PushEvent < ApplicationRecord
  belongs_to :github_event
  belongs_to :actor, optional: true
  belongs_to :repository, optional: true
  
  validates :github_event_id, presence: true, uniqueness: true
  validates :push_id, presence: true
  validates :ref, presence: true
  validates :head, presence: true
  validates :before, presence: true

  scope :by_repository, ->(repo_id) { where(repository_id: repo_id) }
  scope :by_ref, ->(ref) { where(ref: ref) }
  scope :enriched, -> { where.not(enriched_at: nil) }
  scope :unenriched, -> { where(enriched_at: nil) }
  scope :orphaned, -> { where(repository_id: nil) }

  def self.create_from_github_event(github_event)
    raw = github_event.raw_payload
    payload = raw['payload'] || {}

    find_or_create_by(github_event_id: github_event.id) do |record|
      repo_data = raw['repo']
      if repo_data.present?
        repository = Repository.find_or_create_from_payload(repo_data)
        if repository.present?
          record.repository = repository
        else
          Rails.logger.warn("Could not create repository from payload for event #{github_event.id}: #{repo_data.inspect}")
        end
      else
        Rails.logger.warn("No repo data in event #{github_event.id}")
      end

      record.push_id = payload['push_id']
      record.ref = payload['ref']
      record.head = payload['head']
      record.before = payload['before']
    end
  rescue => e
    Rails.logger.error("Failed to create push event from github_event #{github_event.id}: #{e.message}")
    nil
  end

  def orphaned?
    repository_id.nil?
  end

  def enriched?
    enriched_at.present?
  end
end