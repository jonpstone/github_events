class CreateGithubEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :github_events do |t|
      t.references :actor, polymorphic: true, null: true

      t.string :event_id, null: false, index: true
      t.string :event_type, null: false, index: true
      t.string :actor_login
      t.string :actor_avatar_url
      t.string :repo_name
      
      t.bigint :repo_id
      
      t.jsonb :payload, default: {}, null: false
      t.jsonb :raw_payload, null: false

      t.datetime :github_created_at, index: true
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    
    add_index :github_events, [:event_id, :event_type]
  end
end
