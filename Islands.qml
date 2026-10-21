import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Workspace numbers with a border-colored underline on the active one. The
// same widget also restyles the whole bar as islands (IslandPainter.qml), so
// the full look lives in one plugin: put it where the workspaces go.
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

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // Underline colors follow the window border (and so Prism, when it runs)
  readonly property var borderSpec: Border.hyprlandActiveSpec(Color.bar.active, 1)
  readonly property var accentStops: borderSpec.gradient && borderSpec.gradient.enabled && borderSpec.gradient.colors.length > 1
    ? borderSpec.gradient.colors : [borderSpec.color]

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  IslandPainter { host: root }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: modelData === 10 ? "0" : String(modelData)
        opacity: focused ? 1 : (occupied ? 0.7 : 0.35)
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        // Underline under the active workspace
        Rectangle {
          visible: parent.focused && !root.vertical
          width: parent.labelWidth + 4
          height: 2
          radius: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.accentStops[0] }
            GradientStop { position: 1; color: root.accentStops[root.accentStops.length - 1] }
          }
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 5
        }
      }
    }
  }
}
