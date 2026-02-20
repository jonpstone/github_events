class Actor < ApplicationRecord
  has_many :push_events, dependent: :nullify

  validates :github_id, presence: true, uniqueness: true
  validates :login, presence: true

  scope :needs_refresh, -> { where("last_enriched_at IS NULL OR last_enriched_at < ?", 24.hours.ago) }
  scope :already_enriched, -> { where("last_enriched_at > ?", 24.hours.ago) }

  def self.find_or_create_from_payload(actor_data)
    return nil if actor_data.blank?

    github_id = actor_data['id']
    login = actor_data['login']

    find_or_create_by(github_id: github_id) do |actor|
      actor.login = login
      actor.avatar_url = actor_data['avatar_url']
      actor.profile_url = actor_data['html_url']
      actor.actor_type = actor_data['type']
    end
  end

  def should_enrich?
    last_enriched_at.nil? || last_enriched_at < 24.hours.ago
  end

  def mark_enriched(enrichment_data)
    update(enrichment_data.merge(last_enriched_at: Time.current, failed_attempts: 0))
  end

  def mark_failed
    update(failed_attempts: (failed_attempts || 0) + 1)
  end
end
