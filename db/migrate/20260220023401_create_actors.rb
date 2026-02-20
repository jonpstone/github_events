class CreateActors < ActiveRecord::Migration[8.1]
  def change
    create_table :actors do |t|
      t.bigint :github_id, null: false, index: { unique: true }
      t.string :login, null: false, index: true
      t.string :name
      t.text :bio
      t.string :company
      t.string :location
      t.string :email
      t.string :blog
      t.string :twitter_username
      t.integer :followers
      t.integer :following
      t.integer :failed_attempts
      t.datetime :github_created_at
      t.datetime :github_updated_at
      t.string :avatar_url
      t.string :profile_url
      t.string :actor_type, default: 'User'
      t.datetime :last_enriched_at

      t.timestamps
    end
    
    add_index :actors, [:login, :github_id]
  end
end
