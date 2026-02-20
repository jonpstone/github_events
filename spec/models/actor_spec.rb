require 'rails_helper'

RSpec.describe Actor, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:push_events).dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:actor) }

    it { is_expected.to validate_presence_of(:github_id) }
    it { is_expected.to validate_presence_of(:login) }
    it { is_expected.to validate_uniqueness_of(:github_id) }
  end

  describe '.find_or_create_from_payload' do
    context 'with complete payload' do
      let(:payload) do
        {
          'id' => 123,
          'login' => 'octocat',
          'avatar_url' => 'https://avatars.githubusercontent.com/u/1?v=4',
          'html_url' => 'https://github.com/octocat',
          'type' => 'User'
        }
      end

      it 'creates an actor' do
        actor = described_class.find_or_create_from_payload(payload)

        expect(actor).to be_persisted
        expect(actor.github_id).to eq(123)
        expect(actor.login).to eq('octocat')
      end

      it 'returns existing actor if already created' do
        actor1 = described_class.find_or_create_from_payload(payload)
        actor2 = described_class.find_or_create_from_payload(payload)

        expect(actor1.id).to eq(actor2.id)
      end
    end

    context 'with nil payload' do
      it 'returns nil' do
        actor = described_class.find_or_create_from_payload(nil)
        expect(actor).to be_nil
      end
    end

    context 'with blank payload' do
      it 'returns nil' do
        actor = described_class.find_or_create_from_payload({})
        expect(actor).to be_nil
      end
    end
  end

  describe '#should_enrich?' do
    it 'returns true when never enriched' do
      actor = create(:actor, last_enriched_at: nil)
      expect(actor.should_enrich?).to be true
    end

    it 'returns true when stale' do
      actor = create(:actor, last_enriched_at: 25.hours.ago)
      expect(actor.should_enrich?).to be true
    end

    it 'returns false when recently enriched' do
      actor = create(:actor, last_enriched_at: 1.hour.ago)
      expect(actor.should_enrich?).to be false
    end
  end

  describe '#mark_enriched' do
    it 'updates enrichment data' do
      actor = create(:actor, last_enriched_at: nil, failed_attempts: 2)

      actor.mark_enriched(
        name: 'The Octocat',
        followers: 3938,
        following: 9
      )

      actor.reload
      expect(actor.name).to eq('The Octocat')
      expect(actor.followers).to eq(3938)
      expect(actor.following).to eq(9)
      expect(actor.last_enriched_at).to be_within(1.second).of(Time.current)
      expect(actor.failed_attempts).to eq(0)
    end
  end

  describe '#mark_failed' do
    it 'increments failed_attempts' do
      actor = create(:actor, failed_attempts: 1)

      actor.mark_failed
      actor.reload

      expect(actor.failed_attempts).to eq(2)
    end
  end

  describe 'scopes' do
    let!(:needs_refresh) { create(:actor, last_enriched_at: 25.hours.ago) }
    let!(:recently_enriched) { create(:actor, last_enriched_at: 1.hour.ago) }
    let!(:never_enriched) { create(:actor, last_enriched_at: nil) }

    describe '.needs_refresh' do
      it 'returns stale and unenriched actors' do
        expect(described_class.needs_refresh).to contain_exactly(needs_refresh, never_enriched)
      end
    end
  end
end