class CreateJpReferrals < ActiveRecord::Migration[8.1]
  def change
    create_table :jp_referrals do |t|
      t.string :problem_diagnosis_at0002
      t.datetime :problem_diagnosis_at0077
      t.string :problem_diagnosis_at0073
      t.string :story
      t.string :clinical_synopsis
      t.string :clinical_synopsis_2
      t.string :ehr_id
      t.datetime :composed_at
      t.json :rm_composition
      t.string :template_id, null: false, default: 'jp_referral'
      t.string :uid

      t.timestamps
    end
    add_index :jp_referrals, :ehr_id
    add_index :jp_referrals, :uid, unique: true
  end
end
