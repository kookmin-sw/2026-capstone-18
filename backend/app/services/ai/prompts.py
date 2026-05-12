"""Korean prompt templates for tips and weekly reports.

Each builder returns a (system_prompt, user_prompt) tuple to feed into BedrockClient.
"""

from __future__ import annotations

from datetime import date

PHASE_KR = {
    "menstrual": "월경기",
    "follicular": "난포기",
    "ovulation": "배란기",
    "luteal": "황체기",
}


def _phase_label(phase: str) -> str:
    return PHASE_KR.get(phase, phase)


def tip_prompt(
    *,
    display_name: str,
    category_name: str,
    phase: str,
    delta_pct: float,
    event_count: int,
    recent_event_lines: list[str],
) -> tuple[str, str]:
    system = (
        "당신은 친근한 한국어 웰빙 코치입니다. "
        "의학적 조언은 피하고, 짧고 실천 가능한 행동 변화 제안에 집중합니다. "
        "1-2 문장으로만 답하세요. 마크다운, 머리말, 인사 표현은 쓰지 마세요."
    )
    recent = "\n".join(f"- {line}" for line in recent_event_lines) or "- (최근 이벤트 없음)"
    user = (
        f"사용자: {display_name}\n"
        f"패턴:\n"
        f"- 카테고리: {category_name}\n"
        f"- 사이클 단계: {_phase_label(phase)}\n"
        f"- 평소 대비 +{delta_pct:.0f}%\n"
        f"- 이벤트 수: {event_count}회\n\n"
        f"최근 관련 이벤트:\n{recent}\n\n"
        "이 사용자에게 도움이 될 짧고 친근한 팁을 한국어로 작성해 주세요."
    )
    return system, user


def morning_tip_prompt(
    *,
    display_name: str,
    phase: str,
    cycle_day: int | None,
    sleep_minutes: int | None,
    sleep_rating: str | None,
    top_pattern_line: str | None,
) -> tuple[str, str]:
    system = (
        "당신은 사용자의 아침 컨텍스트를 보고 짧은 한국어 신호 메시지를 만드는 어시스턴트입니다. "
        "어젯밤 수면, 현재 생리주기 단계, 최근 스트레스 패턴을 종합해 오늘을 위한 부드러운 제안을 작성합니다. "
        "의학적 진단·단정적 표현은 피하고, 친근하고 실천 가능한 톤을 유지하세요. "
        "반드시 다음 JSON 스키마로만 답하세요. JSON 외 텍스트는 출력하지 마세요.\n\n"
        "스키마:\n"
        "{\n"
        '  "headline": "20자 이내, 오늘의 한 줄 신호",\n'
        '  "body": "2-3 문장, 왜 그렇게 제안하는지와 구체적 행동",\n'
        '  "context_line": "아주 짧은 컨텍스트 한 줄 (예: \\"어젯밤 5h 30m · 황체기\\"), 50자 이내"\n'
        "}"
    )
    sleep_block = (
        f"- 어젯밤 수면: {sleep_minutes}분 ({sleep_rating or '평점 없음'})"
        if sleep_minutes is not None
        else "- 어젯밤 수면: 기록 없음"
    )
    phase_block = f"- 사이클 단계: {_phase_label(phase)}" + (
        f" {cycle_day}일차" if cycle_day else ""
    )
    pattern_block = (
        f"- 최근 관찰된 패턴: {top_pattern_line}"
        if top_pattern_line
        else "- 최근 관찰된 패턴: 없음"
    )
    user = (
        f"사용자: {display_name}\n"
        f"오늘 아침 컨텍스트:\n"
        f"{sleep_block}\n"
        f"{phase_block}\n"
        f"{pattern_block}\n\n"
        "위 컨텍스트로 오늘 아침에 보낼 짧은 신호 메시지를 JSON으로 출력하세요."
    )
    return system, user


def weekly_report_prompt(
    *,
    display_name: str,
    week_start: date,
    week_end: date,
    n_events: int,
    events_summary_lines: list[str],
    n_sleep: int,
    avg_sleep_min: int,
    avg_rating: str,
    sleep_lines: list[str],
    current_phase: str,
    phase_changes: str,
    top_pattern_lines: list[str],
) -> tuple[str, str]:
    system = (
        "당신은 사용자의 7일간 스트레스/수면/생리 데이터를 종합해 한국어 주간 리포트를 작성하는 어시스턴트입니다. "
        "답변은 반드시 다음 JSON 스키마에 맞춰 출력하세요. JSON 외 다른 텍스트는 출력하지 마세요. "
        "의학적 진단을 피하고, 관찰된 패턴과 행동 제안을 부드러운 어조로 전달합니다.\n\n"
        "스키마:\n"
        "{\n"
        '  "headline": "한 줄 요약, 25자 이내",\n'
        '  "body_md": "마크다운 본문 3-4 문단",\n'
        '  "takeaways": [\n'
        '    {"title": "10자 이내 제목", "body": "1-2 문장 요약"}\n'
        "  ]\n"
        "}\n"
        "takeaways는 최대 5개입니다."
    )
    events_block = "\n".join(f"- {x}" for x in events_summary_lines) or "- (이벤트 없음)"
    sleep_block = "\n".join(f"- {x}" for x in sleep_lines) or "- (수면 기록 없음)"
    patterns_block = "\n".join(f"- {x}" for x in top_pattern_lines) or "- (해당 없음)"

    user = (
        f"사용자: {display_name}\n"
        f"이번 주 ({week_start.isoformat()} ~ {week_end.isoformat()}):\n\n"
        f"스트레스 이벤트 ({n_events}건):\n{events_block}\n\n"
        f"수면 ({n_sleep}건):\n"
        f"- 평균 {avg_sleep_min}분, 평균 평점 {avg_rating}\n"
        f"{sleep_block}\n\n"
        f"사이클: 현재 단계 {_phase_label(current_phase)}, 주중 단계 변화: {phase_changes}\n\n"
        f"기존 발견된 통계 패턴:\n{patterns_block}\n\n"
        "위 데이터를 바탕으로 이 주의 리포트를 JSON으로 출력하세요."
    )
    return system, user


def range_report_prompt(
    *,
    display_name: str,
    period_start: date,
    period_end: date,
    n_events: int,
    events_summary_lines: list[str],
    n_sleep: int,
    avg_sleep_min: int,
    avg_rating: str,
    sleep_lines: list[str],
    current_phase: str,
    phase_changes: str,
    top_pattern_lines: list[str],
) -> tuple[str, str]:
    n_days = (period_end - period_start).days + 1
    system = (
        f"당신은 사용자의 {n_days}일간 스트레스/수면/생리 데이터를 종합해 "
        "한국어 리포트를 작성하는 어시스턴트입니다. "
        "답변은 반드시 다음 JSON 스키마에 맞춰 출력하세요. JSON 외 다른 텍스트는 출력하지 마세요. "
        "의학적 진단을 피하고, 관찰된 패턴과 행동 제안을 부드러운 어조로 전달합니다.\n\n"
        "스키마:\n"
        "{\n"
        '  "headline": "한 줄 요약, 25자 이내",\n'
        '  "body_md": "마크다운 본문 3-4 문단",\n'
        '  "takeaways": [\n'
        '    {"title": "10자 이내 제목", "body": "1-2 문장 요약"}\n'
        "  ]\n"
        "}\n"
        "takeaways는 최대 5개입니다."
    )
    events_block = "\n".join(f"- {x}" for x in events_summary_lines) or "- (이벤트 없음)"
    sleep_block = "\n".join(f"- {x}" for x in sleep_lines) or "- (수면 기록 없음)"
    patterns_block = "\n".join(f"- {x}" for x in top_pattern_lines) or "- (해당 없음)"
    user = (
        f"사용자: {display_name}\n"
        f"기간 ({period_start.isoformat()} ~ {period_end.isoformat()}, {n_days}일):\n\n"
        f"스트레스 이벤트 ({n_events}건):\n{events_block}\n\n"
        f"수면 ({n_sleep}건):\n"
        f"- 평균 {avg_sleep_min}분, 평균 평점 {avg_rating}\n"
        f"{sleep_block}\n\n"
        f"사이클: 현재 단계 {_phase_label(current_phase)}, 기간 중 단계 변화: {phase_changes}\n\n"
        f"기존 발견된 통계 패턴:\n{patterns_block}\n\n"
        "위 데이터를 바탕으로 이 기간의 리포트를 JSON으로 출력하세요."
    )
    return system, user
