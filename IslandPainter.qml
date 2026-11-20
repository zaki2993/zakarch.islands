import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons

// Turns the top/bottom bar into three floating machined-glass islands — left,
// center, right — with top specular lighting, a cursor-tracking rim spotlight,
// hairline section dividers, icon micro-hover pills, and full Prism support.
Item {
  id: root

  required property var host
  readonly property var bar: host ? host.bar : null
  readonly property bool vertical: bar ? bar.vertical === true : false

  readonly property int sideGap: 10
  readonly property int inset: 3
  readonly property real pad: Style.space(8)
  readonly property bool glass: bar ? bar.transparent === true : false
  readonly property color fill: Color.bar.background
  readonly property color fgColor: bar ? bar.barForeground : Color.bar.text

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
    if (attached()) {
      tuneIcons()
      for (var i = 0; i < islands.length; i++) {
        if (islands[i] && typeof islands[i].updateDivider === "function") islands[i].updateDivider()
      }
      return
    }
    detach()

    var win = host ? host.QsWindow.window : null
    if (!win || !win.contentItem) return
    var groups = findGroups(win.contentItem)
    if (groups.length === 0) return

    var made = []
    var handlers = []
    var edges = []
    var allSec = []
    for (var g = 0; g < groups.length; g++) {
      var group = groups[g]
      allSec = allSec.concat(group.sections)

      var groupHandlers = []
      for (var s = 0; s < group.sections.length; s++) {
        var handler = hoverComponent.createObject(group.sections[s])
        if (handler) groupHandlers.push(handler)
      }
      handlers = handlers.concat(groupHandlers)
      made.push(islandComponent.createObject(group.parent, {
        region: group.region,
        sections: group.sections,
        handlers: groupHandlers
      }))

      if (group.region === "left" || group.region === "right") {
        for (var e = 0; e < group.sections.length; e++) {
          var list = group.sections[e]
          if (group.region === "left") list.anchors.leftMargin = root.sideGap + root.pad
          else list.anchors.rightMargin = root.sideGap + root.pad
          edges.push(list)
        }
      }
    }

    var right = []
    for (var r = 0; r < groups.length; r++) if (groups[r].region === "right") right = right.concat(groups[r].sections)
    rightSections = right
    allSections = allSec
    tuneIcons()

    win.color = "transparent"
    barWindow = win
    edgeLists = edges
    hoverHandlers = handlers
    islands = made

    for (var m = 0; m < islands.length; m++) {
      if (islands[m] && typeof islands[m].updateDivider === "function") islands[m].updateDivider()
    }
  }

  function detach() {
    untuneIcons()
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

  // Subtle concentric hover capsule + calm resting opacity & tactile micro-lift
  Component {
    id: iconHoverPillComponent

    Rectangle {
      id: pill
      required property var targetButton
      property var canvas: null
      property real restOpacity: 0.86
      property real hoverScale: targetButton && targetButton.tooltipHovered ? 1.07 : 1.0
      property real iconOpacity: targetButton && targetButton.tooltipHovered ? 1.0 : restOpacity

      z: -1
      visible: targetButton && !targetButton.vertical && targetButton.visible
      anchors.centerIn: parent
      width: targetButton ? Math.max(18, targetButton.width - 4) : 0
      height: targetButton ? Math.max(18, targetButton.height - 12) : 0
      radius: height / 2
      color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.09)
      opacity: targetButton && targetButton.tooltipHovered ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
      Behavior on hoverScale {
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
      }
      Behavior on iconOpacity {
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
      }

      Binding {
        target: pill.canvas
        property: "scale"
        value: pill.hoverScale
        when: pill.canvas !== null
      }
      Binding {
        target: pill.canvas
        property: "opacity"
        value: pill.iconOpacity
        when: pill.canvas !== null
      }
    }
  }

  // ── even icons + micro-hover pills ────────────────────────────────────────
  readonly property real iconGap: Style.space(14)
  property var rightSections: []
  property var allSections: []
  property var tunedIcons: []
  property var iconHoverButtons: []
  property var iconHoverPills: []

  FontMetrics { id: iconMetrics; font.family: Style.font.family; font.pixelSize: Style.bar.iconFont }

  function iconFontFor(text) {
    var r = iconMetrics.tightBoundingRect(text)
    if (r.width <= 0 || r.height <= 0) return Style.bar.iconFont
    var target = Style.bar.iconFont * 0.92
    var scale = Math.max(0.9, Math.min(1.1, target / Math.sqrt(r.width * r.height)))
    return Style.bar.iconFont * scale
  }

  function isIconButton(item) {
    return item && ("glyphPaintedWidth" in item) && ("slotSize" in item) && ("opticalSize" in item)
  }

  function tuneIcon(btn) {
    btn.fontSize = Qt.binding(function() { return btn.labelVisible ? Style.font.body : root.iconFontFor(btn.text) })
    btn.fixedWidth = Qt.binding(function() {
      if (btn.vertical || btn.labelVisible) return -1
      return (btn.iconComponent !== null ? btn.opticalSize : btn.glyphPaintedWidth) + root.iconGap
    })
  }

  function restoreIcon(btn) {
    btn.fontSize = Qt.binding(function() { return btn.labelVisible ? Style.font.body : Style.bar.iconFont })
    btn.fixedWidth = Qt.binding(function() { return btn.vertical || btn.labelVisible ? -1 : btn.slotSize })
  }

  function findOpticalCanvas(btn) {
    if (!btn || !btn.children) return null
    for (var i = 0; i < btn.children.length; i++) {
      var child = btn.children[i]
      if (child && Math.abs(child.width - btn.opticalSize) < 0.5 && Math.abs(child.height - btn.opticalSize) < 0.5)
        return child
    }
    return null
  }

  function attachHoverPill(btn) {
    if (iconHoverButtons.indexOf(btn) !== -1) return
    var canvas = findOpticalCanvas(btn)
    var pill = iconHoverPillComponent.createObject(btn, { targetButton: btn, canvas: canvas })
    if (pill) {
      iconHoverButtons.push(btn)
      iconHoverPills.push(pill)
    }
  }

  function tuneIcons() {
    var tuned = tunedIcons.filter(function(b) { return b && b.parent })
    var queue = rightSections.filter(function(s) { return s && s.parent })
    while (queue.length) {
      var item = queue.shift()
      if (isIconButton(item)) {
        if (tuned.indexOf(item) === -1) {
          tuneIcon(item)
          tuned.push(item)
        }
        attachHoverPill(item)
        continue
      }
      var kids = item && item.children ? item.children : []
      for (var k = 0; k < kids.length; k++) queue.push(kids[k])
    }
    tunedIcons = tuned

    // Also give icon buttons in left/center islands (like omarchy.menu) the same crisp hover pill
    var allQueue = allSections.filter(function(s) { return s && s.parent })
    while (allQueue.length) {
      var node = allQueue.shift()
      if (isIconButton(node)) {
        attachHoverPill(node)
        continue
      }
      var children = node && node.children ? node.children : []
      for (var c = 0; c < children.length; c++) allQueue.push(children[c])
    }
  }

  function untuneIcons() {
    for (var i = 0; i < tunedIcons.length; i++) if (tunedIcons[i] && tunedIcons[i].parent) restoreIcon(tunedIcons[i])
    for (var p = 0; p < iconHoverPills.length; p++) if (iconHoverPills[p]) iconHoverPills[p].destroy()
    tunedIcons = []
    iconHoverButtons = []
    iconHoverPills = []
    rightSections = []
    allSections = []
  }

  // ── system widget boundary helper (for hairline dividers) ─────────────────
  readonly property var systemModules: ({
    "zakarch.audio": true,
    "omarchy.audio": true,
    "zakarch.monitor": true,
    "omarchy.monitor": true,
    "zakarch.power": true,
    "omarchy.power": true,
    "omarchy.battery": true,
    "zakarch.network": true,
    "omarchy.network": true,
    "omarchy.bluetooth": true
  })

  function collectSlots(sections) {
    var slots = []
    var queue = sections.slice()
    while (queue.length) {
      var item = queue.shift()
      if (!item || !item.visible) continue
      if (("moduleName" in item) && ("region" in item) && item.width > 0) {
        slots.push(item)
        continue
      }
      var kids = item.children ? item.children : []
      for (var i = 0; i < kids.length; i++) queue.push(kids[i])
    }
    return slots
  }

  // ── one machined-glass island ─────────────────────────────────────────────
  Component {
    id: islandComponent

    Item {
      id: island

      property string region: ""
      property var sections: []
      property var handlers: []

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

      readonly property point pointerPos: {
        for (var i = 0; i < handlers.length; i++) {
          var h = handlers[i]
          if (h && h.hovered && h.parent) {
            return Qt.point(h.parent.x + h.point.position.x - island.x,
                            h.parent.y + h.point.position.y - island.y)
          }
        }
        return Qt.point(island.width / 2, island.height / 2)
      }

      property real lastPointerX: width / 2
      property real lastPointerY: height / 2
      onPointerPosChanged: {
        if (hovered) {
          lastPointerX = pointerPos.x
          lastPointerY = pointerPos.y
        }
      }

      // Hairline divider position in island coordinates (-1 when none)
      property real dividerX: -1
      function updateDivider() {
        if (region !== "left" && region !== "right") { dividerX = -1; return }
        var slots = root.collectSlots(sections)
        if (slots.length < 2) { dividerX = -1; return }

        // Sort left-to-right in island coordinates
        var mapped = []
        for (var i = 0; i < slots.length; i++) {
          var pt = slots[i].mapToItem(island, 0, 0)
          mapped.push({ slot: slots[i], x: pt.x, w: slots[i].width, name: String(slots[i].moduleName || "") })
        }
        mapped.sort(function(a, b) { return a.x - b.x })

        if (region === "left") {
          for (var l = 1; l < mapped.length; l++) {
            if (mapped[l].name === "zakarch.islands" || mapped[l].name === "omarchy.workspaces") {
              dividerX = Math.round(mapped[l].x + 2)
              return
            }
          }
          dividerX = -1
          return
        }

        if (region === "right") {
          var seenTool = false
          for (var r = 0; r < mapped.length; r++) {
            var isSys = !!root.systemModules[mapped[r].name]
            if (isSys && seenTool) {
              var prevRight = mapped[r - 1].x + mapped[r - 1].w
              dividerX = Math.round((prevRight + mapped[r].x) / 2) + 1
              return
            }
            if (!isSys) seenTool = true
          }
        }
        dividerX = -1
      }

      onWidthChanged: updateDivider()
      onXChanged: updateDivider()

      readonly property var range: span()
      readonly property var ends: root.endpoints(island)
      readonly property real radius: height / 2
      readonly property real effectiveTint: Math.max(0.045, root.tintAlpha)
      property real borderLevel: hovered ? 0.68 : 0.36

      Behavior on borderLevel { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

      z: -1
      visible: range.to > range.from
      x: range.from - root.pad
      width: range.to - range.from + root.pad * 2
      y: root.inset
      height: parent ? parent.height - root.inset * 2 : 0

      Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      // Soft two-step drop shadow beneath the island
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2.5
        anchors.bottomMargin: -2.5
        radius: island.radius
        color: Qt.rgba(0, 0, 0, 0.16)
      }
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: -1
        radius: island.radius
        color: Qt.rgba(0, 0, 0, 0.28)
      }

      // Base machined surface
      Rectangle {
        anchors.fill: parent
        radius: island.radius
        color: {
          var base = root.glass
            ? Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 0.42)
            : Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 0.94)
          return island.hovered ? Qt.lighter(base, 1.14) : base
        }
        Behavior on color { ColorAnimation { duration: 160 } }
      }

      // Vertical surface depth sheen (soft top ambient light -> subtle underside shade)
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeWidth: -1
          fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: 0; y2: island.height
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.065) }
            GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.01) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.14) }
          }
          PathSvg { path: root.roundRect(0, 0, island.width, island.height, island.radius) }
        }
      }

      // Subtle ambient accent wash (scales seamlessly with Prism glow)
      Shape {
        anchors.fill: parent
        visible: island.effectiveTint > 0
        opacity: island.effectiveTint * root.breath
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

      // Delicate top inner specular catchlight (glass bevel feel)
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeWidth: -1
          fillRule: ShapePath.OddEvenFill
          fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: 0; y2: island.height
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, island.hovered ? 0.22 : 0.16) }
            GradientStop { position: 0.38; color: Qt.rgba(1, 1, 1, 0.03) }
            GradientStop { position: 0.65; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
          }
          PathSvg {
            path: root.roundRect(root.lineWidth, root.lineWidth,
                                 island.width - root.lineWidth * 2,
                                 island.height - root.lineWidth * 2,
                                 island.radius - root.lineWidth)
              + " "
              + root.roundRect(root.lineWidth + 1, root.lineWidth + 1,
                               island.width - (root.lineWidth + 1) * 2,
                               island.height - (root.lineWidth + 1) * 2,
                               island.radius - (root.lineWidth + 1))
          }
        }
      }

      // Refined outer border ring in Prism / theme accent colors
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

      // Cursor-tracking specular border spotlight
      Shape {
        anchors.fill: parent
        opacity: island.hovered ? 0.95 : 0
        visible: opacity > 0.01
        preferredRendererType: Shape.CurveRenderer

        Behavior on opacity {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        ShapePath {
          strokeWidth: -1
          fillRule: ShapePath.OddEvenFill
          fillGradient: RadialGradient {
            centerX: island.lastPointerX
            centerY: island.lastPointerY
            focalX: island.lastPointerX
            focalY: island.lastPointerY
            centerRadius: 72
            GradientStop { position: 0.0; color: Qt.lighter(root.stopColor(0), 1.35) }
            GradientStop { position: 0.45; color: Qt.rgba(root.stopColor(0).r, root.stopColor(0).g, root.stopColor(0).b, 0.45) }
            GradientStop { position: 1.0; color: Qt.rgba(root.stopColor(0).r, root.stopColor(0).g, root.stopColor(0).b, 0.0) }
          }
          PathSvg {
            path: root.roundRect(0, 0, island.width, island.height, island.radius) + " "
              + root.roundRect(root.lineWidth, root.lineWidth, island.width - root.lineWidth * 2,
                               island.height - root.lineWidth * 2, island.radius - root.lineWidth)
          }
        }
      }

      // Subtle vertical hairline divider (Menu | Workspaces on left, Tools | System on right)
      Rectangle {
        visible: island.dividerX > 8 && island.dividerX < island.width - 8
        x: island.dividerX
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: Math.max(10, Math.round(island.height * 0.44))
        radius: 0.5
        color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.16)
      }
    }
  }
}
