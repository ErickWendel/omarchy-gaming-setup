import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  // Omarchy's theme logs in the last user only; this copy adds a user line
  // that Up/Down/Tab or a click cycles (omarchy-gaming-setup, steam-guest).
  property string currentUser: users.currentItem ? users.currentItem.login : userModel.lastUser
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 40

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    ListView {
      id: users
      model: userModel
      width: entry.width
      height: 36
      anchors.horizontalCenter: parent.horizontalCenter
      orientation: ListView.Horizontal
      interactive: false
      clip: true
      keyNavigationWraps: true
      highlightMoveDuration: 0
      highlightRangeMode: ListView.StrictlyEnforceRange
      preferredHighlightBegin: 0
      preferredHighlightEnd: width
      currentIndex: userModel.lastIndex

      delegate: Text {
        property string login: model.name
        width: users.width
        height: users.height
        text: (userModel.count > 1 ? "‹  " : "") + (model.realName || model.name) + (userModel.count > 1 ? "  ›" : "")
        color: "#a9b1d6"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 22
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.nextUser(mouse.x < width / 2 ? -1 : 1)
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "\u2022"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              sddm.login(root.currentUser, password.text, root.sessionIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
              root.nextUser(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
              root.nextUser(1)
              event.accepted = true
            }
          }
        }
      }
    }

  }

  function nextUser(step) {
    if (users.count < 2)
      return
    users.currentIndex = (users.currentIndex + step + users.count) % users.count
    password.text = ""
    loginFailed = false
    password.forceActiveFocus()
  }

  Component.onCompleted: password.forceActiveFocus()
}
