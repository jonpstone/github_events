class Repository < ApplicationRecord
  has_many :push_events, dependent: :nullify

  validates :github_id, presence: true, uniqueness: true
  validates :full_name, presence: true

  scope :needs_refresh, -> { where("last_enriched_at IS NULL OR last_enriched_at < ?", 24.hours.ago) }
  scope :already_enriched, -> { where("last_enriched_at > ?", 24.hours.ago) }
  scope :by_language, ->(lang) { where(language: lang) }
  scope :popular, -> { order(stars_count: :desc) }

  def self.find_or_create_from_payload(repo_data)
    return nil if repo_data.blank?

    github_id = repo_data['id']
    full_name = repo_data['full_name']

    find_or_create_by(github_id: github_id) do |repo|
      repo.full_name = full_name
      repo.name = repo_data['name']
      repo.description = repo_data['description']
      repo.language = repo_data['language']
      repo.repository_url = repo_data['html_url']
      repo.clone_url = repo_data['clone_url']
      repo.default_branch = repo_data['default_branch']
      repo.stars_count = repo_data['stargazers_count']
      repo.forks_count = repo_data['forks_count']
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