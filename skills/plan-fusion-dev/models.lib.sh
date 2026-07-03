#!/usr/bin/env bash
# ⚠️ 자동 생성 — 수동 수정 금지. models.yaml 편집 후 sync-models.sh 재실행.
# generated_from: /Users/macpro/project/makeskill/models.yaml
# generated_at: 2026-07-03

# shellcheck shell=bash
# 이 파일을 source 하면 아래 변수·헬퍼를 쓸 수 있다(check-fusion.sh 등).

MODELS_VERSION=1
MODELS_GENERATED_AT="2026-07-03"

# disabled (사용자 정책 — 참가자·Judge·Synth·폴백 전 역할 라우팅 금지)
MODELS_DISABLED="fable-5 mythos-5"

# 모델별 변수 (키 = 패널 슬러그). M_<ID>_<ATTR> 형식.
M_GPT_CLI="gpt-5.5"
M_GPT_FAMILY="gpt"
M_GPT_BACKEND="codex"
M_GPT_EFFORT="-c model_reasoning_effort=xhigh"
M_GPT_DIR="-C"

M_GPT_FAST_CLI="gpt-5.5-fast"
M_GPT_FAST_FAMILY="gpt"
M_GPT_FAST_BACKEND="codex"
M_GPT_FAST_EFFORT_TEMPLATE="-c model_reasoning_effort={v}"
M_GPT_FAST_DIR="-C"

M_GPT_54_CLI="gpt-5.4"
M_GPT_54_FAMILY="gpt"
M_GPT_54_BACKEND="codex"
M_GPT_54_EFFORT_TEMPLATE="-c model_reasoning_effort={v}"
M_GPT_54_DIR="-C"

M_SPARK_CLI="gpt-5.3-codex-spark"
M_SPARK_FAMILY="gpt"
M_SPARK_BACKEND="codex"
M_SPARK_DIR="-C"

M_GLM_CLI="zai-coding-plan/glm-5.2"
M_GLM_FAMILY="glm"
M_GLM_BACKEND="opencode"
M_GLM_VARIANT="--variant high"
M_GLM_DIR="-d"
M_GLM_DIR_ALT="--dir"

M_GLM_51_CLI="zai-coding-plan/glm-5.1"
M_GLM_51_FAMILY="glm"
M_GLM_51_BACKEND="opencode"
M_GLM_51_VARIANT="--variant high"
M_GLM_51_DIR="-d"
M_GLM_51_DIR_ALT="--dir"

M_KIMI_CLI="opencode-go/kimi-k2.7-code"
M_KIMI_FAMILY="kimi"
M_KIMI_BACKEND="opencode"
M_KIMI_VARIANT="--variant high"
M_KIMI_DIR="-d"
M_KIMI_DIR_ALT="--dir"

M_KIMI_26_CLI="opencode-go/kimi-k2.6"
M_KIMI_26_FAMILY="kimi"
M_KIMI_26_BACKEND="opencode"
M_KIMI_26_VARIANT="--variant high"
M_KIMI_26_DIR="-d"
M_KIMI_26_DIR_ALT="--dir"

M_DEEPSEEK_CLI="opencode-go/deepseek-v4-pro"
M_DEEPSEEK_FAMILY="glm"
M_DEEPSEEK_BACKEND="opencode"
M_DEEPSEEK_VARIANT="--variant high"
M_DEEPSEEK_DIR="-d"
M_DEEPSEEK_DIR_ALT="--dir"

M_QWEN_CLI="opencode-go/qwen3.7-max"
M_QWEN_FAMILY="glm"
M_QWEN_BACKEND="opencode"
M_QWEN_VARIANT="--variant high"
M_QWEN_DIR="-d"
M_QWEN_DIR_ALT="--dir"

M_MINIMAX_CLI="opencode-go/minimax-m3"
M_MINIMAX_FAMILY="glm"
M_MINIMAX_BACKEND="opencode"
M_MINIMAX_VARIANT="--variant high"
M_MINIMAX_DIR="-d"
M_MINIMAX_DIR_ALT="--dir"

M_GEMINI_CLI="Gemini 3.1 Pro (High)"
M_GEMINI_FAMILY="gemini"
M_GEMINI_BACKEND="agy"

M_GEMINI_FLASH_CLI="Gemini 3.5 Flash (Medium)"
M_GEMINI_FLASH_FAMILY="gemini"
M_GEMINI_FLASH_BACKEND="agy"

M_OPUS_CLI="opus"
M_OPUS_FAMILY="claude"
M_OPUS_BACKEND="claude"

M_OPUS_REVIEW_CLI="dgrid/claude-opus-4-8"
M_OPUS_REVIEW_FAMILY="claude"
M_OPUS_REVIEW_BACKEND="opencode"
M_OPUS_REVIEW_DIR="--dir"

# 패널 프리셋 (슬러그 공백分隔) — 오케스트레이터 동족 제거는 check-fusion.sh 런타임 적용
PANEL_FUSION_DEFAULT_PARTICIPANTS="gpt gemini glm kimi"
PANEL_FUSION_SYNTH="gpt"
PANEL_DEFAULT_2="gpt glm"
PANEL_DEFAULT_3="gpt glm kimi"
PANEL_FUSION_JUDGE="opus"

# disabled 검사 헬퍼(check-fusion.sh 의 _is_disabled_model 대체).
# 반환: 0=금지 아님(사용 가능), 1=금지(routing 금지).
is_disabled_model() {
  [ -z "$MODELS_DISABLED" ] && return 0
  case "$1" in
    *fable-5* | *mythos-5*) return 1 ;;
    *) return 0 ;;
  esac
}

# 라우팅 헬퍼: 슬러그 → 속성 조회. 미정의 시 빈 값. 예: read_model glm CLI
read_model() {
  local _id="$1" _attr="$2" _u _var _val
  _u=$(printf "%s" "$_id" | tr "[:lower:]" "[:upper:]" | tr -cs "[:alnum:]" "[_]")
  _var="M_${_u}_${_attr}"
  eval "_val=\"\${$_var:-}\""
  printf "%s\n" "$_val"
}
