class CreatePushEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :push_events do |t|
      t.references :github_event, null: false, foreign_key: true, index: true
      t.references :actor, foreign_key: { to_table: :actors }, null: true

      t.bigint :repository_id, null: false, index: true

      t.string :push_id, null: false, index: true
      t.string :ref, null: false, index: true
      t.string :head, null: false, index: true
      t.string :before, null: false, index: true

      t.datetime :enriched_at, index: true
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
  end
end
