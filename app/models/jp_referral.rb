# Generated from openEHR template jp_referral by openehr:scaffold.
class JpReferral < ApplicationRecord
  include OpenehrRails::Storable
  include OpenehrRails::AqlQueryable

  TEMPLATE_ID = 'jp_referral'
  ROOT_ARCHETYPE_ID = 'openEHR-EHR-COMPOSITION.request.v1'

  # Single source of truth linking columns to openEHR RM paths and types.
  FIELD_MAP = {
    'problem_diagnosis_at0002' => {label: "プロブレム・診断の名称", path: "/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-EVALUATION.problem_diagnosis.v1]/data[at0001]/items[at0002]/value", rm_type: "DV_CODED_TEXT", rm_type_alternatives: ["DV_CODED_TEXT", "DV_TEXT"], node_id: "at0002", archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", entry_rm_type: "EVALUATION", column_type: :string, value_set_uri: "terminology:http://id.who.int/icd/release/11/mms", code_bindings: [], required: false, code_list: [], code_labels: {}, terminology_id: nil},
    'problem_diagnosis_at0077' => {label: "発症日時", path: "/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-EVALUATION.problem_diagnosis.v1]/data[at0001]/items[at0077]/value", rm_type: "DV_DATE_TIME", rm_type_alternatives: ["DV_DATE_TIME"], node_id: "at0077", archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", entry_rm_type: "EVALUATION", column_type: :datetime, value_set_uri: nil, code_bindings: [], required: false},
    'problem_diagnosis_at0073' => {label: "診断確度", path: "/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-EVALUATION.problem_diagnosis.v1]/data[at0001]/items[at0073]/value", rm_type: "DV_CODED_TEXT", rm_type_alternatives: ["DV_CODED_TEXT", "DV_TEXT"], node_id: "at0073", archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", entry_rm_type: "EVALUATION", column_type: :string, value_set_uri: nil, code_bindings: [], required: false, code_list: ["at0074", "at0075", "at0076"], code_labels: {"at0074" => "疑い", "at0075" => "推定", "at0076" => "確定"}, terminology_id: "local"},
    'story' => {label: "病歴の記述", path: "/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-OBSERVATION.story.v1]/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value", rm_type: "DV_TEXT", rm_type_alternatives: ["DV_TEXT"], node_id: "at0004", archetype_id: "openEHR-EHR-OBSERVATION.story.v1", entry_rm_type: "OBSERVATION", column_type: :string, value_set_uri: nil, code_bindings: [], required: false},
    'clinical_synopsis' => {label: "治療経過", path: "/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-EVALUATION.clinical_synopsis.v1]/data[at0001]/items[at0002]/value", rm_type: "DV_TEXT", rm_type_alternatives: ["DV_TEXT"], node_id: "at0002", archetype_id: "openEHR-EHR-EVALUATION.clinical_synopsis.v1", entry_rm_type: "EVALUATION", column_type: :string, value_set_uri: nil, code_bindings: [], required: false},
    'clinical_synopsis_2' => {label: "治療経過", path: "/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-EVALUATION.clinical_synopsis.v1]/data[at0001]/items[at0002]/value", rm_type: "DV_TEXT", rm_type_alternatives: ["DV_TEXT"], node_id: "at0002", archetype_id: "openEHR-EHR-EVALUATION.clinical_synopsis.v1", entry_rm_type: "EVALUATION", column_type: :string, value_set_uri: nil, code_bindings: [], required: false}
  }.freeze

end
