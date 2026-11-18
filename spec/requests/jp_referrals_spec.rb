require 'rails_helper'

RSpec.describe '/jp_referrals', type: :request do
  let(:valid_attributes) do
    {
      problem_diagnosis_at0002: 'test',
      problem_diagnosis_at0077: Time.current,
      problem_diagnosis_at0073: "at0074",
      story: 'test',
      clinical_synopsis: 'test',
      clinical_synopsis_2: 'test',
    }
  end

  describe 'GET /index' do
    it 'renders a successful response' do
      JpReferral.create!(valid_attributes)
      get jp_referrals_url
      expect(response).to be_successful
    end
  end

  describe 'GET /show' do
    it 'renders a successful response' do
      record = JpReferral.create!(valid_attributes)
      get jp_referral_url(record)
      expect(response).to be_successful
    end
  end

  describe 'POST /create' do
    it 'creates a new record and the RM composition' do
      expect do
        post jp_referrals_url, params: { jp_referral: valid_attributes }
      end.to change(JpReferral, :count).by(1)

      expect(JpReferral.last.rm_composition['_type']).to eq('COMPOSITION')
    end
  end

  describe 'DELETE /destroy' do
    it 'destroys the record' do
      record = JpReferral.create!(valid_attributes)
      expect do
        delete jp_referral_url(record)
      end.to change(JpReferral, :count).by(-1)
    end
  end
end
