import QtQuick

Item {
  id: root

  property bool opened: false

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }
}
