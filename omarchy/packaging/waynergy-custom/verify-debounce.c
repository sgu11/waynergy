#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

struct wlContext {
	long wheel_debounce_ms;
	int wheel_last_dir[2];
	uint32_t wheel_last_ts[2];
	bool wheel_just_reversed[2];
	uint32_t fake_now;
};
static uint32_t wlTS(struct wlContext *ctx) { return ctx->fake_now; }
static void logDbg(const char *fmt, ...) { (void)fmt; }

#include "extracted.inc"

/* 실측 y축 반전 간격 (ms) 과 그 분류.
 * bounce = 엔코더 바운스(폐기 대상), real = 사람이 의도한 전환(통과 대상)
 *
 * 두 차례 실측을 합쳤다.
 *  - 2026-08-26 14:3x, debounce off, 수신 99건 → 반전 27건
 *  - 2026-08-26 14:47, debounce 60ms, 수신 130건 → 폐기 11건 + 통과 6건
 *
 * 두 번째 회차의 78ms 건은 폐기되지 않고 통과했으나 바운스로 분류한다.
 * 근거는 문맥이다 — 앞뒤가 (-120,-120 → +120 하나 → -120,-120) 으로 단발
 * 반전 후 즉시 복귀한다. 의도한 전환이면 전환 뒤 같은 방향이 이어지는데
 * (통과한 나머지 5건은 모두 그렇다) 이 건만 그렇지 않다. */
struct sample { double gap; int bounce; };
static struct sample S[] = {
	/* 1회차: off 상태에서 관측한 반전 27건 */
	{1.2,1},{1.8,1},{2.0,1},{2.7,1},{4.6,1},{4.9,1},{6.0,1},{7.0,1},{7.1,1},
	{8.5,1},{9.1,1},{9.7,1},{12.6,1},{15.0,1},{17.1,1},{19.7,1},{19.8,1},
	{24.5,1},{25.4,1},{28.6,1},{31.2,1},
	{241.6,0},{243.8,0},{270.5,0},{798.9,0},{1068.2,0},{1110.5,0},
	/* 2회차: 60ms 로 폐기된 11건 */
	{3,1},{3,1},{4,1},{6,1},{6,1},{7,1},{9,1},{11,1},{14,1},{18,1},{20,1},
	/* 2회차: 60ms 를 통과한 6건 — 78 만 바운스다 */
	{78,1},{202,0},{214,0},{257,0},{258,0},{306,0},
};

static bool run(long thresh)
{
	int drop_ok=0, drop_bad=0, pass_ok=0, pass_bad=0, n_bounce=0, n_real=0;
	for (unsigned i=0;i<sizeof(S)/sizeof(*S);++i) { if (S[i].bounce) n_bounce++; else n_real++; }
	for (unsigned i=0;i<sizeof(S)/sizeof(*S);++i) {
		struct wlContext ctx = {0};
		ctx.wheel_debounce_ms = thresh;
		/* 선행 노치: 아래로 (dy = -120), t=0 */
		ctx.fake_now = 0;
		wheel_debounce(&ctx, 1, -120);
		/* 반전 노치: 위로 (dy = +120), t=gap */
		ctx.fake_now = (uint32_t)(S[i].gap + 0.5);
		bool dropped = wheel_debounce(&ctx, 1, 120);
		if (dropped) { if (S[i].bounce) drop_ok++; else drop_bad++; }
		else         { if (S[i].bounce) pass_bad++; else pass_ok++; }
	}
	printf("  T=%4ldms  바운스 폐기 %2d/%d   정상 통과 %d/%d   %s\n",
		thresh, drop_ok, n_bounce, pass_ok, n_real,
		(drop_bad||pass_bad) ? "실패" : "완전 분류");
	if (pass_bad) printf("            └ 놓친 바운스 %d건\n", pass_bad);
	if (drop_bad) printf("            └ 씹은 정상 전환 %d건\n", drop_bad);
	return drop_bad == 0 && pass_bad == 0;
}

int main(void)
{
	printf("[임계값별 실측 %zu건 분류]\n", sizeof(S)/sizeof(*S));
	bool samples_ok = true;
	for (long t = 0; t <= 300; t += (t<50?5:(t<160?10:40))) {
		if (t) {
			bool ok = run(t);
			if (t == 100) samples_ok = ok;
		}
	}

	printf("\n[상태 갱신 규칙: 폐기된 노치는 기준을 갱신하지 않는가]\n");
	struct wlContext c = {0}; c.wheel_debounce_ms = 60;
	c.fake_now = 0;   printf("  t=  0 down : %s\n", wheel_debounce(&c,1,-120)?"폐기":"통과");
	c.fake_now = 5;   printf("  t=  5 up   : %s\n", wheel_debounce(&c,1, 120)?"폐기":"통과");
	c.fake_now = 10;  printf("  t= 10 up   : %s  (기준이 t=0/down 그대로면 폐기)\n", wheel_debounce(&c,1,120)?"폐기":"통과");
	c.fake_now = 300; printf("  t=300 up   : %s  (임계 밖이므로 통과해야 정상)\n", wheel_debounce(&c,1,120)?"폐기":"통과");

	printf("\n[축 독립성]\n");
	struct wlContext a = {0}; a.wheel_debounce_ms = 60;
	a.fake_now = 0; wheel_debounce(&a,1,-120);
	a.fake_now = 5; printf("  y로 down 후 5ms 뒤 x로 up: %s  (독립이면 통과)\n", wheel_debounce(&a,0,120)?"폐기":"통과");

	printf("\n[비활성 기본값 0]\n");
	struct wlContext z = {0};
	z.fake_now = 0; wheel_debounce(&z,1,-120);
	z.fake_now = 1; printf("  debounce_ms=0, 1ms 뒤 반전: %s  (통과해야 정상)\n", wheel_debounce(&z,1,120)?"폐기":"통과");

	printf("\n[실제 로그 시퀀스 재생 — 100ms]\n");
	/* (dy, 직전 노치로부터의 간격 ms). 2026-08-26 15:04:37 구간 실측.
	 * 바운스가 창을 넘겨 통과한 뒤, 사용자의 복귀가 씹히던 자리다. */
	struct step { int dy; int gap; const char *want; };
	static struct step SEQ[] = {
		{-120,   0, "통과"},   /* 아래로 */
		{ 120, 150, "통과"},   /* 창을 넘긴 바운스 — 막을 수 없다 */
		{-120,  10, "통과"},   /* 사용자의 복귀 — 절대 씹으면 안 된다 */
		{-120,  20, "통과"},
		{-120,  25, "통과"},
		{ 120,   5, "폐기"},   /* 버스트 한가운데 바운스 */
		{-120,  15, "통과"},
	};
	struct wlContext q = {0}; q.wheel_debounce_ms = 100; q.fake_now = 0;
	int seq_ok = 1;
	for (unsigned i=0;i<sizeof(SEQ)/sizeof(*SEQ);++i) {
		q.fake_now += SEQ[i].gap;
		const char *got = wheel_debounce(&q,1,SEQ[i].dy) ? "폐기" : "통과";
		int ok = !strcmp(got, SEQ[i].want);
		if (!ok) seq_ok = 0;
		printf("  dy=%+4d  +%3dms  →  %s   (기대 %s) %s\n",
			SEQ[i].dy, SEQ[i].gap, got, SEQ[i].want, ok?"":"  ← 불일치");
	}
	printf("  %s\n", seq_ok ? "시퀀스 통과" : "시퀀스 실패");

	printf("\n[uint32 랩어라운드]\n");
	struct wlContext w = {0}; w.wheel_debounce_ms = 60;
	w.fake_now = 0xFFFFFFF0u; wheel_debounce(&w,1,-120);
	w.fake_now = 0x00000005u; /* 21ms 경과, 랩 */
	printf("  0xFFFFFFF0 -> 0x00000005 (21ms): %s  (폐기해야 정상)\n", wheel_debounce(&w,1,120)?"폐기":"통과");

	printf("\n[유휴 후 새 방향 전환 — 회귀 방지]\n");
	/* 오래전 반대 방향(+1, 위)으로 스크롤하고 멈춘 상태. 지금 아래로 새로
	 * 시작한다. follow-up 의 보호 플래그가 여기서 잘못 켜지면, 첫 바운스가
	 * 새어나가고 사용자의 복귀 노치가 씹힌다(2026-08-27 실측 회귀). */
	struct wlContext h = {0}; h.wheel_debounce_ms = 100;
	h.wheel_last_dir[1] = 1; h.wheel_last_ts[1] = 0; h.fake_now = 60000;
	h.fake_now += 0;  printf("  t=60000 down : %s  (통과해야 정상)\n", wheel_debounce(&h,1,-120)?"폐기":"통과");
	h.fake_now += 15; printf("  t=+15   up   : %s  (바운스이므로 폐기해야 정상)\n", wheel_debounce(&h,1,120)?"폐기":"통과");
	h.fake_now += 30; printf("  t=+30   down : %s  (사용자 복귀이므로 통과해야 정상)\n", wheel_debounce(&h,1,-120)?"폐기":"통과");
	int idle_ok = 1;
	{
		struct wlContext i = {0}; i.wheel_debounce_ms = 100;
		i.wheel_last_dir[1] = 1; i.wheel_last_ts[1] = 0; i.fake_now = 60000;
		i.fake_now += 0;  if (wheel_debounce(&i,1,-120)) idle_ok = 0;
		i.fake_now += 15; if (!wheel_debounce(&i,1,120)) idle_ok = 0;
		i.fake_now += 30; if (wheel_debounce(&i,1,-120)) idle_ok = 0;
	}
	printf("  %s\n", idle_ok ? "유휴 후 전환 통과" : "유휴 후 전환 실패 — 바운스가 새거나 복귀가 씹힌다");
	return !(samples_ok && seq_ok && idle_ok);
}
