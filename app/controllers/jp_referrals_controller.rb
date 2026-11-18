class JpReferralsController < ApplicationController
  before_action :set_jp_referral, only: %i[show edit update destroy]

  # GET /jp_referrals
  def index
    @jp_referrals = JpReferral.all

    respond_to do |format|
      format.html
      format.json { render json: @jp_referrals }
    end
  end

  # GET /jp_referrals/1
  def show
    respond_to do |format|
      format.html
      format.json { render json: @jp_referral }
    end
  end

  # GET /jp_referrals/new
  def new
    @jp_referral = JpReferral.new
  end

  # GET /jp_referrals/1/edit
  def edit
  end

  # POST /jp_referrals
  def create
    @jp_referral = JpReferral.new(jp_referral_params)

    respond_to do |format|
      if @jp_referral.save
        format.html { redirect_to jp_referral_url(@jp_referral), notice: 'Jp referral was successfully created.' }
        format.json { render json: @jp_referral, status: :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @jp_referral.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /jp_referrals/1
  def update
    respond_to do |format|
      if @jp_referral.update(jp_referral_params)
        format.html { redirect_to jp_referral_url(@jp_referral), notice: 'Jp referral was successfully updated.' }
        format.json { render json: @jp_referral, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @jp_referral.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /jp_referrals/1
  def destroy
    @jp_referral.destroy!

    respond_to do |format|
      format.html { redirect_to jp_referrals_url, notice: 'Jp referral was successfully destroyed.', status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_jp_referral
    @jp_referral = JpReferral.find(params[:id])
  end

  def jp_referral_params
    params.require(:jp_referral).permit(:problem_diagnosis_at0002, :problem_diagnosis_at0077, :problem_diagnosis_at0073, :story, :clinical_synopsis, :clinical_synopsis_2)
  end
end
