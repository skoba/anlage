# 定義の組の画面（読むだけ。skoba/anlage#296、docs/design/definition-registration-plan.md 4 節、R-20261128-7）。
# 書き込み（登録・動かす・戻す）は rake だけ。検査の結果は、いまのテンプレートで検査し直したもの（Definitions::ActiveScreen.lint）
class DefinitionsController < ApplicationController
  def index
    @bundles = DefinitionBundle.order(:bundle_id, id: :desc).to_a
    @reports = @bundles.to_h { [ _1.id, Definitions::ActiveScreen.lint(_1) ] }
  end

  def show
    @bundle = DefinitionBundle.find(params[:id])
    @report = Definitions::ActiveScreen.lint(@bundle)
    @previous = DefinitionBundle.where(bundle_id: @bundle.bundle_id).where(id: ...@bundle.id).order(id: :desc).first
    @diff = Definitions::FileDiff.call(@previous.files, @bundle.files) if @previous
  end
end
