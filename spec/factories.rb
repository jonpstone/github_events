FactoryBot.define do
  factory :github_event do
    event_id { SecureRandom.uuid }
    event_type { 'PushEvent' }
    actor_login { 'octocat' }
    repo_name { 'octocat/Hello-World' }
    repo_id { 1296269 }
    raw_payload do
      {
        'id' => event_id,
        'type' => event_type,
        'actor' => {
          'id' => 1,
          'login' => actor_login,
          'avatar_url' => 'https://avatars.githubusercontent.com/u/1?v=4',
          'html_url' => 'https://github.com/octocat',
          'type' => 'User'
        },
        'repo' => {
          'id' => repo_id,
          'name' => repo_name,
          'url' => "https://api.github.com/repos/#{repo_name}"
        },
        'payload' => {
          'push_id' => rand(1_000_000),
          'ref' => 'refs/heads/main',
          'head' => SecureRandom.hex(20),
          'before' => SecureRandom.hex(20)
        },
        'created_at' => Time.current.iso8601
      }
    end
    payload do
      raw_payload['payload']
    end
    github_created_at { Time.current }

    trait :issues_event do
      event_type { 'IssuesEvent' }
    end

    trait :pr_event do
      event_type { 'PullRequestEvent' }
    end
  end

  factory :push_event do
    github_event
    push_id { "push_#{SecureRandom.hex(8)}" }
    ref { 'refs/heads/main' }
    head { SecureRandom.hex(20) }
    before { SecureRandom.hex(20) }
    repository { nil }
    actor { nil }
    enriched_at { nil }
  end

  factory :repository do
    github_id { rand(1_000_000..9_999_999) }
    sequence(:full_name) { |n| "user#{n}/repo#{n}" }
    name { full_name.split('/').last }
    description { Faker::Lorem.sentence }
    language { 'Ruby' }
    repository_url { "https://github.com/#{full_name}" }
    clone_url { "https://github.com/#{full_name}.git" }
    default_branch { 'main' }
    stars_count { rand(0..10000) }
    forks_count { rand(0..1000) }
    watchers_count { rand(0..5000) }
    is_fork { false }
    is_private { false }
    last_enriched_at { nil }
    failed_attempts { 0 }
  end

  factory :actor do
    github_id { rand(1_000_000..9_999_999) }
    sequence(:login) { |n| "user#{n}" }
    avatar_url { 'https://avatars.githubusercontent.com/u/1?v=4' }
    profile_url { "https://github.com/#{login}" }
    actor_type { 'User' }
    name { Faker::Name.name }
    bio { Faker::Lorem.sentence }
    company { Faker::Company.name }
    location { Faker::Address.city }
    followers { rand(0..10000) }
    following { rand(0..1000) }
    public_repos { rand(0..500) }
    last_enriched_at { nil }
    failed_attempts { 0 }
  end
end