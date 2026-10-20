module TemplatesHelper
  # 登録版（registry 連番）とテンプレート版（OPT の sem_ver）の並記（skoba/anlage#47、ui-vocabulary.md）
  def version_label(version, sem_ver)
    [ "登録版 v#{version}", ("テンプレート版 #{sem_ver}" if sem_ver) ].compact.join("／")
  end
end
