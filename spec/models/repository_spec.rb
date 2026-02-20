require 'rails_helper'

RSpec.describe Repository, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:push_events).dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:repository) }

    it { is_expected.to validate_presence_of(:github_id) }
    it { is_expected.to validate_presence_of(:full_name) }
    it { is_expected.to validate_uniqueness_of(:github_id) }
  end

  describe '.find_or_create_from_payload' do
    context 'with complete payload' do
      let(:payload) do
        {
          'id' => 12345,
          'full_name' => 'user/my-repo',
          'name' => 'my-repo',
          'description' => 'A test repo',
          'stargazers_count' => 100,
          'forks_count' => 5,
          'language' => 'Ruby'
        }
      end

      it 'creates a repository' do
        repo = described_class.find_or_create_from_payload(payload)

        expect(repo).to be_persisted
        expect(repo.github_id).to eq(12345)
        expect(repo.full_name).to eq('user/my-repo')
        expect(repo.stars_count).to eq(100)
      end

      it 'returns existing repository if already created' do
        repo1 = described_class.find_or_create_from_payload(payload)
        repo2 = described_class.find_or_create_from_payload(payload)

        expect(repo1.id).to eq(repo2.id)
      end
    end

    context 'with missing github_id' do
      it 'returns nil' do
        payload = { 'id' => nil, 'full_name' => 'user/repo' }
        repo = described_class.find_or_create_from_payload(payload)

        expect(repo).to be_nil
      end
    end

    context 'with missing full_name' do
      it 'uses name as fallback' do
        payload = {
          'id' => 12345,
          'name' => 'user/my-repo',
          'full_name' => nil
        }

        repo = described_class.find_or_create_from_payload(payload)

        expect(repo.full_name).to eq('user/my-repo')
      end
    end

    context 'with blank payload' do
      it 'returns nil' do
        repo = described_class.find_or_create_from_payload(nil)
        expect(repo).to be_nil
      end
    end
  end

  describe 'caching logic' do
    describe '#should_enrich?' do
      it 'returns true when never enriched' do
        repo = create(:repository, last_enriched_at: nil)
        expect(repo.should_enrich?).to be true
      end

      it 'returns true when stale (> 24 hours)' do
        repo = create(:repository, last_enriched_at: 25.hours.ago)
        expect(repo.should_enrich?).to be true
      end

      it 'returns false when recently enriched' do
        repo = create(:repository, last_enriched_at: 1.hour.ago)
        expect(repo.should_enrich?).to be false
      end

      it 'returns false when enriched exactly 24 hours ago' do
        repo = create(:repository, last_enriched_at: 24.hours.ago)
        expect(repo.should_enrich?).to be false
      end
    end

    describe '#mark_enriched' do
      it 'updates enrichment data and timestamp' do
        repo = create(:repository, last_enriched_at: nil, failed_attempts: 3)

        repo.mark_enriched(
          description: 'Updated',
          stars_count: 200,
          language: 'Python'
        )

        repo.reload
        expect(repo.description).to eq('Updated')
        expect(repo.stars_count).to eq(200)
        expect(repo.language).to eq('Python')
        expect(repo.last_enriched_at).to be_within(1.second).of(Time.current)
        expect(repo.failed_attempts).to eq(0)
      end
    end

    describe '#mark_failed' do
      it 'increments failed_attempts' do
        repo = create(:repository, failed_attempts: 2)

        repo.mark_failed
        repo.reload

        expect(repo.failed_attempts).to eq(3)
      end
    end
  end

  describe 'scopes' do
    let!(:needs_refresh) { create(:repository, last_enriched_at: 25.hours.ago) }
    let!(:recently_enriched) { create(:repository, last_enriched_at: 1.hour.ago) }
    let!(:never_enriched) { create(:repository, last_enriched_at: nil) }

    describe '.needs_refresh' do
      it 'returns stale and unenriched repositories' do
        expect(described_class.needs_refresh).to contain_exactly(needs_refresh, never_enriched)
      end
    end

    describe '.by_language' do
      let!(:ruby_repo) { create(:repository, language: 'Ruby') }
      let!(:python_repo) { create(:repository, language: 'Python') }

      it 'returns repositories by language' do
        expect(described_class.by_language('Ruby')).to contain_exactly(ruby_repo)
      end
    end

    describe '.popular' do
      let!(:popular) { create(:repository, stars_count: 1000) }
      let!(:unpopular) { create(:repository, stars_count: 10) }

      it 'returns repositories ordered by stars' do
        expect(described_class.popular.first).to eq(popular)
        expect(described_class.popular.last).to eq(unpopular)
      end
    end
  end
end