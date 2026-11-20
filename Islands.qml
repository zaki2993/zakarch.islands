import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Workspace numbers with a smoothly gliding glass capsule on the active one
// and subtle occupied dots. The same widget also restyles the whole bar as
// machined-glass islands (IslandPainter.qml).
BarWidget {
  id: root
  moduleName: "zakarch.islands"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  // Workspaces 1-5 always, plus any other one (up to 10) that is in use
  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property var ids: workspaceIds()
  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property int activeIndex: ids.indexOf(focusedId)

  readonly property real slotWidth: Style.space(24)
  readonly property real slotSpacing: Style.space(2)
  readonly property real leadingGap: root.vertical ? 0 : Style.spaceReal(6)
  readonly property real trailingGap: 0
  readonly property real pillHeight: Math.max(18, root.barSize - 12)

  // Accent colors follow the window border (and Prism, when it runs)
  readonly property var borderSpec: Border.hyprlandActiveSpec(Color.bar.active, 1)
  readonly property var accentStops: borderSpec.gradient && borderSpec.gradient.enabled && borderSpec.gradient.colors.length > 1
    ? borderSpec.gradient.colors : [borderSpec.color]
  readonly property color accentPrimary: accentStops[0]
  readonly property color accentSecondary: accentStops[accentStops.length - 1]
  readonly property color fgColor: root.bar ? root.bar.barForeground : Color.bar.text

  implicitWidth: leadingGap + grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  IslandPainter { host: root }

  Item {
    id: track
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.leftMargin: root.leadingGap
    anchors.right: parent.right
    anchors.rightMargin: root.trailingGap

    // Smoothly gliding active workspace capsule
    Rectangle {
      id: activeCapsule
      visible: !root.vertical && root.activeIndex >= 0
      z: 0
      x: root.activeIndex >= 0 ? root.activeIndex * (root.slotWidth + root.slotSpacing) : 0
      anchors.verticalCenter: parent.verticalCenter
      width: root.slotWidth
      height: root.pillHeight
      radius: height / 2
      color: Qt.rgba(root.accentPrimary.r, root.accentPrimary.g, root.accentPrimary.b, 0.16)
      border.width: 1
      border.color: Qt.rgba(root.accentPrimary.r, root.accentPrimary.g, root.accentPrimary.b, 0.42)

      Behavior on x {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
      }

      // Subtle inner top glint on the active workspace pill
      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, parent.radius - 1)
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
          GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.06) }
        }
      }
    }

    GridLayout {
      id: grid
      z: 1
      anchors.fill: parent
      columns: root.vertical ? 1 : root.ids.length
      columnSpacing: root.vertical ? 0 : root.slotSpacing
      rowSpacing: root.vertical ? Style.space(2) : 0

      Repeater {
        model: root.ids

        WidgetButton {
          id: wsBtn
          required property int modelData

          readonly property var workspace: root.workspaceById(modelData)
          readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
          readonly property bool focused: root.focusedId === modelData

          bar: root.bar
          text: modelData === 10 ? "0" : String(modelData)
          opacity: focused ? 1.0 : (occupied ? 0.78 : 0.34)
          horizontalMargin: 4
          verticalPadding: 4
          fixedWidth: root.vertical ? root.barSize : root.slotWidth
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(modelData) }

          // Soft hover pill for inactive workspaces
          Rectangle {
            z: -1
            visible: !wsBtn.focused && !root.vertical
            anchors.centerIn: parent
            width: parent.width
            height: root.pillHeight
            radius: height / 2
            color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.08)
            opacity: wsBtn.tooltipHovered ? 1 : 0

            Behavior on opacity {
              NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
          }

          // Subtle occupied indicator dot for unfocused workspaces with open windows
          Rectangle {
            visible: wsBtn.occupied && !wsBtn.focused && !root.vertical
            width: 3
            height: 3
            radius: 1.5
            color: Qt.rgba(root.accentPrimary.r, root.accentPrimary.g, root.accentPrimary.b, 0.7)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6.5
          }
        }
      }
    }
  }
}
