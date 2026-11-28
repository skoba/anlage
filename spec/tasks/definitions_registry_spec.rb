require "rails_helper"

# 定義の組の登録の入口（docs/design/definition-registration-plan.md 4 節、skoba/anlage#279、R-20261128-7 の回答 5）。
# 認証が無いあいだ、書き込み（登録・動かす・戻す）は rake だけ。サーバのシェルに入れる運用者が使う
RSpec.describe "定義の組の rake（register・activate・restore・list）" do
  let(:dir) { Rails.root.join("spec/fixtures/definitions/clinic") }

  before do
    %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
      Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
    end
  end

  after { %w[DIR BUNDLE VERSION].each { ENV.delete(_1) } }

  def run_task(name, **env)
    env.each { |key, value| ENV[key.to_s] = value.to_s }
    Rake::Task["definitions:#{name}"].reenable
    Rake::Task["definitions:#{name}"].invoke
  end

  it "register は、検査を通った組を下書きで足し、運用者の名前を registered_by に入れる" do
    expect { run_task(:register, DIR: dir) }.to output(/組 clinic_spec の版 0\.1\.0 を下書きで登録した（id \d+）。案 1 件/).to_stdout

    expect(DefinitionBundle.sole).to have_attributes(status: "draft", registered_by: "rake（#{Etc.getlogin || ENV['USER']}）")
  end

  it "register は、エラーの文を出して終了コード 1（足さない）" do
    broken = Pathname(Dir.mktmpdir).join("clinic").tap { FileUtils.cp_r(dir, _1) }
    broken.join("screens/lab_entry.yml").write(broken.join("screens/lab_entry.yml").read.sub("LabResultReport", "NoSuchTemplate"))

    expect { run_task(:register, DIR: broken) }.to output(/登録しなかった: エラー \d+ 件.*\[D3\]/m).to_stdout
      .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    expect(DefinitionBundle.count).to eq(0)
  ensure
    FileUtils.remove_entry(broken.dirname)
  end

  it "activate で動かし、restore で前の版に戻す。list は組・版・状態を出す" do
    run_task(:register, DIR: dir)
    expect { run_task(:activate, BUNDLE: "clinic_spec", VERSION: "0.1.0") }.to output("組 clinic_spec の版 0.1.0 を動かした\n").to_stdout
    expect { run_task(:restore, BUNDLE: "clinic_spec", VERSION: "0.1.0") }
      .to output("組 clinic_spec の版 0.1.0 の中身を、版 0.1.1 として足して動かした\n").to_stdout

    expect { run_task(:list) }.to output(<<~TEXT).to_stdout
      組 clinic_spec
        0.1.0  superseded
        0.1.1  active（0.1.0 から戻した）
    TEXT
  end

  it "無い組・版は、文を出して終了コード 1" do
    expect { run_task(:activate, BUNDLE: "clinic_spec", VERSION: "9.9.9") }.to output("組 clinic_spec の版 9.9.9 は無い\n").to_stdout
      .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
  end
end
