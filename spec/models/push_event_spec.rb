require 'rails_helper'

RSpec.describe PushEvent, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:github_event) }
    it { is_expected.to belong_to(:actor).optional }
    it { is_expected.to belong_to(:repository).optional }
  end

  describe 'validations' do
    subject { build(:push_event) }

    it { is_expected.to validate_presence_of(:github_event_id) }
    it { is_expected.to validate_presence_of(:push_id) }
    it { is_expected.to validate_presence_of(:ref) }
    it { is_expected.to validate_presence_of(:head) }
    it { is_expected.to validate_presence_of(:before) }
    it { is_expected.to validate_uniqueness_of(:github_event_id) }
  end

  describe '.create_from_github_event' do
    let(:github_event) do
      create(:github_event, raw_payload: {
        'payload' => {
          'repository_id' => 123,
          'push_id' => 'push_123',
          'ref' => 'refs/heads/main',
          'head' => 'abc123',
          'before' => 'def456'
        },
        'repo' => { 'id' => 123, 'name' => 'user/repo', 'url' => 'https://api.github.com/repos/user/repo' }
      })
    end

    it 'creates a push event from github event' do
      push_event = described_class.create_from_github_event(github_event)

      expect(push_event).to be_persisted
      expect(push_event.github_event_id).to eq(github_event.id)
      expect(push_event.push_id).to eq('push_123')
      expect(push_event.ref).to eq('refs/heads/main')
      expect(push_event.head).to eq('abc123')
      expect(push_event.before).to eq('def456')
    end

    it 'handles missing repository_id' do
      github_event.update(raw_payload: github_event.raw_payload.merge('payload' => { 'push_id' => 'test' }))

      push_event = described_class.create_from_github_event(github_event)

      expect(push_event.repository_id).to be_nil
    end

    it 'prevents duplicate push events' do
      push_event1 = described_class.create_from_github_event(github_event)

      expect {
        described_class.create_from_github_event(github_event)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'scopes' do
    let!(:enriched) { create(:push_event, enriched_at: 1.hour.ago) }
    let!(:unenriched) { create(:push_event, enriched_at: nil) }
    let!(:orphaned) { create(:push_event, repository_id: nil, enriched_at: nil) }

    describe '.enriched' do
      it 'returns only enriched events' do
        expect(described_class.enriched).to contain_exactly(enriched)
      end
    end

    describe '.unenriched' do
      it 'returns only unenriched events' do
        expect(described_class.unenriched).to contain_exactly(unenriched, orphaned)
      end
    end

    describe '.orphaned' do
      it 'returns only events without repositories' do
        expect(described_class.orphaned).to contain_exactly(orphaned)
      end
    end

    describe '.by_repository' do
      let(:repo) { create(:repository) }
      let!(:event_with_repo) { create(:push_event, repository: repo) }

      it 'returns events for a specific repository' do
        expect(described_class.by_repository(repo.id)).to contain_exactly(event_with_repo)
      end
    end

    describe '.by_ref' do
      let!(:main_event) { create(:push_event, ref: 'refs/heads/main') }
      let!(:develop_event) { create(:push_event, ref: 'refs/heads/develop') }

      it 'returns events for a specific ref' do
        expect(described_class.by_ref('refs/heads/main')).to contain_exactly(main_event)
      end
    end
  end

  describe '#enriched?' do
    it 'returns true when enriched_at is present' do
      push_event = create(:push_event, enriched_at: 1.hour.ago)
      expect(push_event.enriched?).to be true
    end

    it 'returns false when enriched_at is nil' do
      push_event = create(:push_event, enriched_at: nil)
      expect(push_event.enriched?).to be false
    end
  end
end