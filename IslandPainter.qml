import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons

// Restyles the stock bar that `host` (a bar widget) sits in: the bar window
// turns clear and each section (left, center, right) floats as a rounded
// island. Sections are found by shape (items with `region`), so if a future
// bar changes its internals the islands just stop showing.
//
// The island borders follow Prism: the colors come from the shell's
// hyprland.active-border token (which Prism keeps in sync), laid out as one
// gradient across the whole bar, and Prism's spin / breathe / glow settings
// animate it. Hovering an island brightens it.
Item {
  id: root

  property Item host: null
  readonly property var bar: host ? host.bar : null
  readonly property bool vertical: host ? host.vertical : false

  // The side gap matches Hyprland's gaps_out so islands line up with windows.
  readonly property int sideGap: 10
  readonly property int inset: 3
  readonly property real pad: Style.space(7)
  readonly property bool glass: bar ? bar.transparent === true : false
  readonly property color fill: Color.bar.background

  // ── Prism link ────────────────────────────────────────────────────────────
  readonly property var borderSpec: Border.hyprlandActiveSpec(Color.bar.active, 1)
  readonly property bool hasGradient: !!borderSpec.gradient && borderSpec.gradient.enabled
                                      && borderSpec.gradient.colors.length > 1
  readonly property var stops: hasGradient ? borderSpec.gradient.colors : [borderSpec.color]
  readonly property real lineWidth: Math.max(1, Border.uniformWidth(borderSpec))
  readonly property real angle: (hasGradient ? borderSpec.gradient.angle : 0) + spinOffset

  // Effect levels mirror Prism's Engine.js tables.
  property var prism: ({})
  readonly property bool prismOn: prism.enabled === true
  readonly property int spinMs: prismOn ? [0, 10000, 5000, 2500, 1000][prism.spin || 0] || 0 : 0
  readonly property int breathMs: prismOn ? [0, 2600, 1300][prism.breathe || 0] || 0 : 0
  readonly property real tintAlpha: prismOn ? [0, 0.08, 0.14, 0.22][prism.glow || 0] || 0 : 0

  property real spinOffset: 0
  property real breath: 1

  function stopColor(i) { return i < stops.length ? stops[i] : stops[stops.length - 1] }
  function stopPos(i) { return stops.length <= 1 ? (i === 0 ? 0 : 1) : Math.min(1, i / (stops.length - 1)) }

  // One gradient across the whole bar, expressed in the island's own coordinates.
  function endpoints(island) {
    var w = island.parent ? island.parent.width : island.width
    var h = island.height
    var rad = root.angle * Math.PI / 180
    var dx = Math.cos(rad)
    var dy = Math.sin(rad)
    var len = (Math.abs(w * dx) + Math.abs(h * dy)) / 2
    var cx = w / 2 - island.x
    var cy = h / 2
    return { x1: cx - dx * len, y1: cy - dy * len, x2: cx + dx * len, y2: cy + dy * len }
  }

  function roundRect(x, y, w, h, r) {
    r = Math.max(0, Math.min(r, w / 2, h / 2))
    return "M" + (x + r) + "," + y
      + " H" + (x + w - r) + " A" + r + "," + r + " 0 0 1 " + (x + w) + "," + (y + r)
      + " V" + (y + h - r) + " A" + r + "," + r + " 0 0 1 " + (x + w - r) + "," + (y + h)
      + " H" + (x + r) + " A" + r + "," + r + " 0 0 1 " + x + "," + (y + h - r)
      + " V" + (y + r) + " A" + r + "," + r + " 0 0 1 " + (x + r) + "," + y + " Z"
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/zakarch.prism/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.prism = JSON.parse(text()) } catch (e) { root.prism = ({}) }
    }
    onLoadFailed: root.prism = ({})
  }

  NumberAnimation {
    id: spinAnim
    target: root
    property: "spinOffset"
    from: 0
    to: 360
    duration: Math.max(1, root.spinMs)
    loops: Animation.Infinite
    running: root.spinMs > 0
    onRunningChanged: if (!running) root.spinOffset = 0
  }
  onSpinMsChanged: if (spinAnim.running) spinAnim.restart()

  SequentialAnimation {
    id: breathAnim
    loops: Animation.Infinite
    running: root.breathMs > 0
    onRunningChanged: if (!running) root.breath = 1

    NumberAnimation { target: root; property: "breath"; to: 0.45; duration: Math.max(1, root.breathMs); easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "breath"; to: 1; duration: Math.max(1, root.breathMs); easing.type: Easing.InOutSine }
  }
  onBreathMsChanged: if (breathAnim.running) breathAnim.restart()

  // ── no hover growth in the center ─────────────────────────────────────────
  // The bar reveals inactive indicators while the center is hovered, which
  // makes the center island grow under the cursor. Keep that suppressed; the
  // clock and weather popups switch it back off when they close.
  function suppressCenterReveal() {
    if (bar && typeof bar.setCenterHoverRevealSuppressed === "function" && !bar.centerHoverRevealSuppressed)
      bar.setCenterHoverRevealSuppressed(true)
  }

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onCenterHoverRevealSuppressedChanged() { root.suppressCenterReveal() }
  }

  // ── finding the bar sections ──────────────────────────────────────────────
  property var islands: []
  property var hoverHandlers: []
  property var edgeLists: []
  property var barWindow: null

  function isSection(item) {
    return item && ("region" in item) && (("entries" in item) || ("entry" in item))
  }

  // Groups top-level section items by parent: left and right lists share the
  // bar row, the center pieces (before, anchor, after) share their own row.
  function findGroups(top) {
    var groups = []
    var stack = [top]
    while (stack.length) {
      var item = stack.pop()
      if (isSection(item)) {
        var group = null
        for (var g = 0; g < groups.length; g++) {
          if (groups[g].parent === item.parent && groups[g].region === item.region) group = groups[g]
        }
        if (!group) {
          group = { parent: item.parent, region: item.region, sections: [] }
          groups.push(group)
        }
        group.sections.push(item)
        continue
      }
      var kids = item && item.children ? item.children : []
      for (var k = 0; k < kids.length; k++) stack.push(kids[k])
    }
    return groups
  }

  function attached() {
    if (islands.length === 0) return false
    for (var i = 0; i < islands.length; i++) if (!islands[i] || !islands[i].parent) return false
    return true
  }

  function refresh() {
    if (vertical) { detach(); return }
    suppressCenterReveal()
    if (attached()) return
    detach()

    var win = host ? host.QsWindow.window : null
    if (!win || !win.contentItem) return
    var groups = findGroups(win.contentItem)
    if (groups.length === 0) return

    var made = []
    var handlers = []
    var edges = []
    for (var g = 0; g < groups.length; g++) {
      var group = groups[g]

      // Hover is tracked on the sections themselves: as ancestors of the
      // widgets they stay hovered while the pointer is over a widget.
      var groupHandlers = []
      for (var s = 0; s < group.sections.length; s++) {
        var handler = hoverComponent.createObject(group.sections[s])
        if (handler) groupHandlers.push(handler)
      }
      handlers = handlers.concat(groupHandlers)
      made.push(islandComponent.createObject(group.parent, { sections: group.sections, handlers: groupHandlers }))

      // Pull the side sections in so their islands sit on the window gap line.
      if (group.region === "left" || group.region === "right") {
        for (var e = 0; e < group.sections.length; e++) {
          var list = group.sections[e]
          if (group.region === "left") list.anchors.leftMargin = root.sideGap + root.pad
          else list.anchors.rightMargin = root.sideGap + root.pad
          edges.push(list)
        }
      }
    }

    win.color = "transparent"
    barWindow = win
    edgeLists = edges
    hoverHandlers = handlers
    islands = made
  }

  function detach() {
    for (var i = 0; i < islands.length; i++) if (islands[i]) islands[i].destroy()
    for (var h = 0; h < hoverHandlers.length; h++) if (hoverHandlers[h]) hoverHandlers[h].destroy()
    for (var e = 0; e < edgeLists.length; e++) {
      if (!edgeLists[e]) continue
      if (edgeLists[e].region === "left") edgeLists[e].anchors.leftMargin = Style.space(8)
      else edgeLists[e].anchors.rightMargin = Style.space(8)
    }
    if (barWindow) {
      var b = root.bar
      barWindow.color = Qt.binding(function() { return b && b.transparent ? "transparent" : Color.bar.background })
    }
    islands = []
    hoverHandlers = []
    edgeLists = []
    barWindow = null
  }

  Component.onDestruction: {
    detach()
    if (bar && typeof bar.setCenterHoverRevealSuppressed === "function") bar.setCenterHoverRevealSuppressed(false)
  }

  // The bar builds its sections asynchronously and rebuilds them when it
  // changes, so keep checking that the islands are still in place.
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component {
    id: hoverComponent
    HoverHandler {}
  }

  // ── one island ────────────────────────────────────────────────────────────
  Component {
    id: islandComponent

    Item {
      id: island

      property var sections: []
      property var handlers: []

      // Span of the visible, non-empty sections in the shared parent's coordinates
      function span() {
        var from = Infinity
        var to = -Infinity
        for (var i = 0; i < sections.length; i++) {
          var s = sections[i]
          if (!s || !s.visible || s.width <= 0) continue
          from = Math.min(from, s.x)
          to = Math.max(to, s.x + s.width)
        }
        return { from: from, to: to }
      }

      readonly property bool hovered: {
        for (var i = 0; i < handlers.length; i++) if (handlers[i] && handlers[i].hovered) return true
        return false
      }
      readonly property var range: span()
      readonly property var ends: root.endpoints(island)
      readonly property real radius: height / 2
      property real borderLevel: hovered ? 1 : 0.7

      Behavior on borderLevel { NumberAnimation { duration: 150 } }

      z: -1
      visible: range.to > range.from
      x: range.from - root.pad
      width: range.to - range.from + root.pad * 2
      y: root.inset
      height: parent ? parent.height - root.inset * 2 : 0

      Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      // Soft two-step shadow just below the island
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.bottomMargin: -2
        radius: island.radius
        color: Qt.rgba(0, 0, 0, 0.12)
      }
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: -1
        radius: island.radius
        color: Qt.rgba(0, 0, 0, 0.22)
      }

      Rectangle {
        anchors.fill: parent
        radius: island.radius
        color: {
          var base = root.glass ? Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 0.35) : root.fill
          return island.hovered ? Qt.lighter(base, 1.35) : base
        }
        Behavior on color { ColorAnimation { duration: 150 } }
      }

      // Prism glow: a faint wash of the border colors inside the island
      Shape {
        anchors.fill: parent
        visible: root.tintAlpha > 0
        opacity: root.tintAlpha * root.breath
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeWidth: -1
          fillGradient: LinearGradient {
            x1: island.ends.x1; y1: island.ends.y1; x2: island.ends.x2; y2: island.ends.y2
            GradientStop { position: root.stopPos(0); color: root.stopColor(0) }
            GradientStop { position: root.stopPos(1); color: root.stopColor(1) }
            GradientStop { position: root.stopPos(2); color: root.stopColor(2) }
            GradientStop { position: root.stopPos(3); color: root.stopColor(3) }
          }
          PathSvg { path: root.roundRect(0, 0, island.width, island.height, island.radius) }
        }
      }

      // Border ring in the Prism colors; calm at rest, full on hover
      Shape {
        anchors.fill: parent
        opacity: root.breath * island.borderLevel
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeWidth: -1
          fillRule: ShapePath.OddEvenFill
          fillGradient: LinearGradient {
            x1: island.ends.x1; y1: island.ends.y1; x2: island.ends.x2; y2: island.ends.y2
            GradientStop { position: root.stopPos(0); color: root.stopColor(0) }
            GradientStop { position: root.stopPos(1); color: root.stopColor(1) }
            GradientStop { position: root.stopPos(2); color: root.stopColor(2) }
            GradientStop { position: root.stopPos(3); color: root.stopColor(3) }
          }
          PathSvg {
            path: root.roundRect(0, 0, island.width, island.height, island.radius) + " "
              + root.roundRect(root.lineWidth, root.lineWidth, island.width - root.lineWidth * 2,
                               island.height - root.lineWidth * 2, island.radius - root.lineWidth)
          }
        }
      }
    }
  }
}
