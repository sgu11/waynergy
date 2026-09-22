/* Exercise the packaged protocol and extracted callbacks without a compositor. */
#include <assert.h>
#include "sig.h"

struct wlContext wlContext;
struct synNetContext synNetContext;
volatile sig_atomic_t sigDoExit, sigDoRestart;
pid_t clipMonitorPid[2];
static bool inhibited;
static int kills;
static uint32_t now = 20000;
static unsigned char incoming[256], sent[256];
static int incoming_len, sent_len, sends, keys;

void Exit(enum sigExitStatus status) { abort(); }
void wlIdleInhibit(struct wlContext *ctx, bool on) { inhibited = on; }
void wlClose(struct wlContext *ctx) {}
bool synNetDisconnect(struct synNetContext *ctx) { return true; }

static int track_kill(pid_t pid, int sig)
{
	assert(pid > 0 && sig == SIGTERM);
	++kills;
	return 0;
}

/* These functions are extracted verbatim from the prepared source. */
#define kill track_kill
#include "cleanup.inc"
#undef kill
#include "sig-handle.inc"
#include "sig-wait.inc"
#include "screensaver.inc"

static bool connect_server(uSynergyCookie cookie) { return true; }
static void sleep_ms(uSynergyCookie cookie, int ms) {}
static uint32_t get_time(void) { return now; }
static bool send_packet(uSynergyCookie cookie, const uint8_t *buf, int len)
{
	assert(len <= sizeof(sent));
	memcpy(sent, buf, len);
	sent_len = len;
	++sends;
	return true;
}
static bool receive_packet(uSynergyCookie cookie, uint8_t *buf, int max, int *len)
{
	assert(incoming_len <= max);
	memcpy(buf, incoming, incoming_len);
	*len = incoming_len;
	incoming_len = 0;
	return true;
}
static void keyboard(uSynergyCookie cookie, uint16_t key, uint16_t id,
                     uint16_t mod, bool down, bool repeat)
{
	assert(id == 65 && key == 30 && down);
	++keys;
}
static void init(uSynergyContext *ctx)
{
	uSynergyInit(ctx);
	ctx->m_clientName = "fork-test";
	ctx->m_useRawKeyCodes = true;
	ctx->m_connectFunc = connect_server;
	ctx->m_sendFunc = send_packet;
	ctx->m_receiveFunc = receive_packet;
	ctx->m_sleepFunc = sleep_ms;
	ctx->m_getTimeFunc = get_time;
	ctx->m_keyboardCallback = keyboard;
	ctx->m_screensaverCallback = syn_screensaver_cb;
	uSynergyUpdate(ctx);
	assert(ctx->m_connected);
}
static void deliver(uSynergyContext *ctx, const unsigned char *body, int len)
{
	assert(len < 256 - 4);
	memset(incoming, 0, 4);
	incoming[3] = len;
	memcpy(incoming + 4, body, len);
	incoming_len = len + 4;
	uSynergyUpdate(ctx);
}
static void hello(uSynergyContext *ctx, const char *name)
{
	unsigned char body[32];
	size_t n = strlen(name);
	memcpy(body, name, n);
	memcpy(body + n, "\0\1\0\10", 4);
	deliver(ctx, body, n + 4);
	assert(ctx->m_hasReceivedHello && sent_len >= n + 8);
	assert(!memcmp(sent + 4, name, n));
	assert(!memcmp(sent + 4 + n, "\0\1\0\10", 4));
}

int main(int argc, char **argv)
{
	assert(argc == 2);
	osConfigPathOverride = argv[1];
	assert(configInitINI());
	assert(logInit(LOG_INFO, NULL));
	uSynergyContext ctx;
	const char *names[] = {"Synergy", "Barrier", "Deskflow"};
	for (size_t i = 0; i < 3; ++i) {
		init(&ctx);
		hello(&ctx, names[i]);
	}
	int before = sends;
	uSynergyUpdateClipBuf(&ctx, 0, 4, "test");
	assert(sends == before && ctx.m_clipGrabPending[0]);
	deliver(&ctx, (unsigned char *)"CINN\0\0\0\0\0\0\0\7\0\0", 14);
	assert(ctx.m_sequenceNumber == 7 && !ctx.m_clipGrabPending[0]);
	assert(sends == before + 2); /* CCLP, then CNOP */
	uSynergyUpdateClipBuf(&ctx, 0, 4, "next");
	assert(!memcmp(sent + 4, "CCLP\0\0\0\0\7", 9));
	deliver(&ctx, (unsigned char *)"DKDL\0\101\0\0\0\36\0\0\0\2en", 16);
	deliver(&ctx, (unsigned char *)"DKRP\0\101\0\0\0\1\0\36\0\0\0\2en", 18);
	assert(keys == 2);
	puts("PASS: protocol 1.8 hellos, deferred clipboard, DKDL/DKRP");

	/* A real system() child must be reaped even with normal SA_NOCLDWAIT. */
	sigWaitSIGCHLD(false);
	deliver(&ctx, (unsigned char *)"CSEC\1", 5);
	assert(!inhibited);
	deliver(&ctx, (unsigned char *)"CSEC\0", 5);
	assert(inhibited);
	deliver(&ctx, (unsigned char *)"CBYE", 4);
	assert(!ctx.m_connected);
	uSynergyUpdate(&ctx);
	hello(&ctx, "Deskflow");
	deliver(&ctx, (unsigned char *)"CSEC\1", 5);
	struct sigaction sa;
	assert(sigaction(SIGCHLD, NULL, &sa) == 0);
	assert(sa.sa_flags & SA_NOCLDWAIT);
	free(ctx.m_clipBuf[0]);
	puts("PASS: CSEC on/off/reconnect and SIGCHLD restoration");

	init(&ctx);
	hello(&ctx, "Deskflow");
	ctx.m_lastMessageTime = 20000;
	now = 19999;
	uSynergyUpdate(&ctx);
	assert(ctx.m_connected);
	now = 30000;
	uSynergyUpdate(&ctx);
	assert(ctx.m_connected);
	now = 30001;
	uSynergyUpdate(&ctx);
	assert(!ctx.m_connected && ctx.m_lastError == USYNERGY_ERROR_TIMEOUT);
	init(&ctx);
	hello(&ctx, "Deskflow");
	ctx.m_lastMessageTime = UINT32_MAX - 15;
	now = 5;
	uSynergyUpdate(&ctx);
	assert(ctx.m_connected);
	puts("PASS: backward ticks, timeout boundary and clock wraparound");

	clipMonitorPid[0] = -1;
	clipMonitorPid[1] = 0;
	cleanup(SES_ERROR_WL);
	assert(kills == 0);
	clipMonitorPid[0] = 1234;
	clipMonitorPid[1] = 5678;
	cleanup(SES_ERROR_WL);
	assert(kills == 2);
	puts("PASS: cleanup signals only positive child PIDs");
	return 0;
}
