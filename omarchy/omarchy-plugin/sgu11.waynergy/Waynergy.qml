import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// waynergy 바 위젯 — 상태 표시 + 왼쪽 클릭으로 여는 패널(서비스 토글,
// 자동 시작 토글, 현재 설정).
//
// 판정은 전부 ~/.local/bin/waynergy-ctl 이 한다. QML 은 그 JSON 한 줄만 읽는다
// (adguard·onlykey 위젯과 같은 이유 — QML 에서 셸 문자열을 조립하지 않는다).
//
// 상태가 두 축인 이유: 유닛은 Restart=always 라 서버가 죽어 있어도 active 로
// 남는다. "실행 중"과 "서버에 붙어 있다"를 나누지 않으면 입력이 안 오는데
// 아이콘은 선명하게 켜져 있다. 연결 판정은 waynergy-ctl 이 실제 소켓으로 한다.
//
// 오른쪽 클릭에 서비스 토글을 걸지 않았다. 이 서비스는 이 세션의 키보드·마우스
// 입력 경로 자체다 — 잘못 누르면 입력이 끊기고, 그 상태에서는 되돌릴 입력 수단이
// 없다. 끄고 켜기는 패널 안에서만 한다.
Panel {
  id: root
  moduleName: "sgu11.waynergy"
  ipcTarget: "sgu11.waynergy"
  // 기본 IpcHandler 를 끄고 아래에서 직접 등록한다 — 패널 여닫기 외에
  // 서비스·자동시작 토글도 IPC 로 내보내기 위해서다 (키바인드에서 부를 수 있다).
  manageIpc: false

  property var info: ({})
  property var action: null
  property string actionPhase: "idle"
  property bool readingStatus: false
  property bool refreshPending: false
  property int cursorIndex: 0          // 0 = 서비스, 1 = 자동 시작, 2 = 디바운스, 3 = 휠 배수
  property int wheelChoiceIndex: 0
  property bool cursorActive: false

  readonly property bool installed: info.installed === true
  readonly property bool busyService: action !== null && action.kind === "service"
  readonly property bool svcActive: busyService ? action.value : info.active === true
  readonly property bool connected: !busyService && info.connected === true
  readonly property bool autostart: action && action.kind === "autostart" ? action.value : info.autostart === true
  readonly property bool debounceSupported: info.wheelDebounceSupported === true
  readonly property real debounceMs: Number(info.wheelDebounceMs) || 0
  readonly property bool debounceEnabled: action && action.kind === "debounce" ? action.value : debounceMs > 0
  readonly property string wheelMult: action && action.kind === "wheel" ? action.value : (info.wheelMult || "1")
  readonly property string server: {
    const host = info.host || "?"
    return (host.includes(":") ? "[" + host + "]" : host) + ":" + (info.port || "?")
  }
  readonly property string tlsStatus: {
    if (!/yes|true|on/.test(info.tls || "")) return "꺼짐"
    const mode = /yes|true|on/.test(info.tofu || "") ? "TOFU" : "서버 지문 확인"
    return mode + (info.pinned === true ? " · 지문 고정됨" : " · 지문 없음")
  }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // 바 아이콘은 단색이다. 색은 쓰지 않고 세 단계 흐림으로만 말한다.
  //   선명   = 연결됨            흐림 0.7 = 실행 중이나 서버 대기
  //   흐림 0.4 = 멈춤 · 미설치
  // Routine polling must not affect opacity. The previous widget included its
  // status processes in a visual `busy` flag, dimming the icon on every poll
  // and producing a periodic flicker. Only a user-requested service mutation
  // may temporarily change the optimistic connection state.
  readonly property real iconOpacity: connected ? 1.0 : (svcActive ? 0.7 : 0.4)

  readonly property string statusMeta: !installed ? "waynergy 없음"
                                     : !svcActive ? "멈춤"
                                     : connected ? "연결됨 · " + server
                                                 : "서버 대기 중 · " + server

  readonly property string tooltip: !installed ? "waynergy 미설치 또는 유닛 없음"
                                  : !svcActive ? "waynergy: 멈춤 — 클릭하면 패널을 연다"
                                  : connected ? "waynergy: " + server + " 에 연결됨"
                                              : "waynergy: 실행 중이나 " + server + " 에 붙지 못했다"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    refreshPending = true
    advance()
  }

  function advance() {
    // A mutation starts after the current read and finishes with a fresh read.
    if (readingStatus || actionPhase === "running") return
    if (actionPhase === "queued") {
      actionPhase = "running"
      actionProc.command = action.command
      actionProc.running = true
    } else if (refreshPending) {
      refreshPending = false
      readingStatus = true
      infoProc.running = true
    }
  }

  function finishStatus(code, text) {
    if (!readingStatus) return
    readingStatus = false
    let snapshot = null
    if (code === 0) {
      try { snapshot = JSON.parse(text) } catch (error) {}
    }
    info = (snapshot && typeof snapshot === "object" && !Array.isArray(snapshot)) ? snapshot : ({})
    if (actionPhase === "confirming") {
      action = null
      actionPhase = "idle"
    }
    Qt.callLater(advance)
  }

  function finishAction() {
    if (actionPhase !== "running") return
    actionPhase = "confirming"
    refreshPending = true
    Qt.callLater(advance)
    settle.restart()
  }

  function runAction(kind, value, args) {
    if (!installed || action !== null) return
    action = { kind: kind, value: value, command: ["waynergy-ctl"].concat(args) }
    actionPhase = "queued"
    advance()
  }

  function toggleService() {
    const start = !svcActive
    runAction("service", start, [start ? "start" : "stop"])
  }

  function toggleAutostart() {
    const enable = !autostart
    runAction("autostart", enable, [enable ? "enable" : "disable"])
  }

  function setWheelMult(value) {
    value = String(value)
    if (!installed || action !== null || ["1", "2", "3"].indexOf(value) < 0 || wheelMult === value) return
    wheelChoiceIndex = Number(value) - 1
    runAction("wheel", value, ["set-wheel-mult", value])
  }

  function toggleDebounce() {
    if (!debounceSupported) return
    const enable = !debounceEnabled
    runAction("debounce", enable, ["set-wheel-debounce", enable ? "on" : "off"])
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy !== 0) {
      cursorIndex = Math.max(0, Math.min(3, cursorIndex + dy))
      if (cursorIndex === 3) wheelChoiceIndex = Math.max(0, ["1", "2", "3"].indexOf(wheelMult))
    } else if (cursorIndex === 3 && dx !== 0) {
      wheelChoiceIndex = Math.max(0, Math.min(2, wheelChoiceIndex + dx))
    }
  }

  function activateCursor() {
    if (cursorIndex === 0) toggleService()
    else if (cursorIndex === 1) toggleAutostart()
    else if (cursorIndex === 2) toggleDebounce()
    else setWheelMult(String(wheelChoiceIndex + 1))
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function toggleService(): string { root.toggleService(); return "ok" }
    function toggleAutostart(): string { root.toggleAutostart(); return "ok" }
    function toggleDebounce(): string { root.toggleDebounce(); return "ok" }
    function setWheelMult(value: string): string { root.setWheelMult(value); return "ok" }
  }

  Process {
    id: infoProc
    command: ["waynergy-ctl", "info"]
    stdout: StdioCollector { id: infoOutput; waitForEnd: true }
    onExited: function (code) { root.finishStatus(code, infoOutput.text) }
    // An executable that fails to start emits runningChanged without exited.
    onRunningChanged: if (!running) root.finishStatus(-1, "")
  }

  Process {
    id: actionProc
    onExited: root.finishAction()
    onRunningChanged: if (!running) root.finishAction()
  }

  Timer {
    id: settle
    interval: 2000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: Math.max(3, root.setting("refreshIntervalSec", 10)) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    useActiveColor: false
    opacity: root.iconOpacity
    tooltipText: root.tooltip
    iconComponent: Component {
      Item {
        DeskflowIcon {
          anchors.centerIn: parent
          iconSize: Style.space(18)
          color: root.barForeground
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      // 한 글자 단축키에 토글을 걸지 않는다. 패널은 열려 있는 동안 키보드
      // 포커스를 가져가므로, 사용자가 다른 창에 타이핑하던 키가 그대로 여기로
      // 들어온다. 실측(2026-08-26): 's' 를 서비스 토글로 두었더니 옆 창에
      // 입력하던 글자가 서비스를 연달아 껐다 켜 systemd start limit 에 걸렸고
      // 원격 키보드·마우스가 통째로 끊겼다. 토글은 스위치 클릭이나, 커서를
      // 직접 옮긴 뒤의 Enter 로만 한다. 읽기 전용인 새로고침만 남긴다.
      onTextKey: function (t) {
        if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // hero 의 trailingControl 안에서 `root` 는 PanelHero 로 풀린다.
            // 패널 상태는 이 `header` 를 통해서만 닿는다 (tailscale 위젯과 동일).
            readonly property bool ringVisible: root.cursorActive && root.cursorIndex === 0 && root.installed
            function focusHero() { root.cursorActive = true; root.cursorIndex = 0 }

            PanelHero {
              id: hero
              width: parent.width
              title: "waynergy"
              meta: root.statusMeta
              detail: root.info.version || ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.connected ? 1.0 : 0.5
              iconComponent: Component {
                DeskflowIcon {
                  iconSize: Style.font.display
                  color: root.foreground
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: root.installed
                  checked: root.svcActive
                  busy: root.busyService
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function (on) { if (on) header.focusHero() }
                  onToggled: root.toggleService()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.svcActive ? "waynergy 를 멈춘다 — 이 세션의 원격 키보드·마우스가 끊긴다"
                                         : "waynergy 를 시작한다"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          CursorSurface {
            visible: !root.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "waynergy 가 없거나 waynergy.service 가 설치되지 않았다.\nyay -S waynergy"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          Toggle {
            visible: root.installed
            width: parent.width
            label: "로그인 시 자동 시작"
            description: "graphical-session.target 에 걸어 둔다"
            checked: root.autostart
            hasCursor: root.cursorActive && root.cursorIndex === 1
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleAutostart()
            onHovered: function (on) { if (on) { root.cursorActive = true; root.cursorIndex = 1 } }
          }

          Toggle {
            visible: root.installed
            width: parent.width
            label: "휠 디바운스"
            description: root.debounceSupported
              ? (root.debounceEnabled
                  ? "반대 방향 노치 필터 · " + (root.debounceMs > 0 ? root.debounceMs : 100) + " ms"
                  : "반대 방향 노치 필터 · 꺼짐")
              : "패치된 waynergy 패키지가 필요합니다"
            checked: root.debounceEnabled
            hasCursor: root.cursorActive && root.cursorIndex === 2
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleDebounce()
            onHovered: function (on) { if (on) { root.cursorActive = true; root.cursorIndex = 2 } }
          }

          CursorSurface {
            visible: root.installed
            width: parent.width
            implicitHeight: wheelRow.implicitHeight + Style.spacing.rowPaddingX
            hasCursor: root.cursorActive && root.cursorIndex === 3
            foreground: root.foreground

            Row {
              id: wheelRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              spacing: Style.space(12)

              Text {
                id: wheelLabel
                anchors.verticalCenter: parent.verticalCenter
                text: "휠 배수"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Item { width: Math.max(0, wheelRow.width - wheelLabel.implicitWidth - wheelChoices.implicitWidth - Style.space(24)); height: 1 }

              ButtonGroup {
                id: wheelChoices
                options: [
                  { value: "1", label: "×1", tooltip: "휠 배수를 1로 설정합니다. 실행 중인 Waynergy가 잠시 재시작됩니다" },
                  { value: "2", label: "×2", tooltip: "휠 배수를 2로 설정합니다. 실행 중인 Waynergy가 잠시 재시작됩니다" },
                  { value: "3", label: "×3", tooltip: "휠 배수를 3으로 설정합니다. 실행 중인 Waynergy가 잠시 재시작됩니다" }
                ]
                value: root.wheelMult
                cursorIndex: root.cursorActive && root.cursorIndex === 3 ? root.wheelChoiceIndex : -1
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function(value) { root.setWheelMult(value) }
                onHovered: function(index, isHovered) {
                  if (isHovered) {
                    root.cursorActive = true
                    root.cursorIndex = 3
                    root.wheelChoiceIndex = index
                  }
                }
              }
            }
          }

          PanelSeparator {
            visible: root.installed
            foreground: root.foreground
          }

          Column {
            visible: root.installed
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "설정"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            InfoRow {
              label: "서버"
              value: root.server
            }
            InfoRow {
              label: "휠 디바운스"
            value: root.debounceMs > 0 ? root.debounceMs + " ms" : "꺼짐"
            }
            InfoRow {
              label: "휠 배수"
              value: "×" + root.wheelMult
            }
            InfoRow {
              label: "raw-keymap"
              value: "offset " + (root.info.keymapOffset || "0")
                     + " · 명시 " + (root.info.keymapExplicit === undefined ? 0 : root.info.keymapExplicit) + "개"
            }
            InfoRow {
              label: "TLS"
              value: root.tlsStatus
            }
            InfoRow {
              label: "로그 레벨"
              value: (root.info.logLevel || "?") + " (유닛이 정한다)"
            }
            InfoRow {
              label: "유닛"
              value: (root.info.unitState || "?") + " / " + (root.info.subState || "?")
            }
          }
        }
      }
    }
  }

  // 설정 한 줄 — 왼쪽 라벨, 오른쪽 값. 값이 길면 값 쪽을 줄인다.
  component InfoRow: Item {
    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: valueText
      anchors.left: labelText.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }
}
