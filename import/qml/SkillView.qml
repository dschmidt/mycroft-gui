/*
 *   Copyright 2018 by Marco Martin <mart@kde.org>
 *   Copyright 2018 David Edmundson <davidedmundson@kde.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU Library General Public License as
 *   published by the Free Software Foundation; either version 2, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Library General Public License for more details
 *
 *   You should have received a copy of the GNU Library General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

import QtQuick 2.4
import QtQuick.Controls 2.4
import org.kde.kirigami 2.4 as Kirigami
import Mycroft 1.0 as Mycroft

//FIXME: we probably want to wrap this in an Item or Control as we don't want to expose full StackView api
Item {
    id: root

    property alias initialItem: mainStack.initialItem
    property alias pushEnter: mainStack.pushEnter
    property alias pushExit: mainStack.pushExit
    property alias popEnter: mainStack.popEnter
    property alias popExit: mainStack.popExit
    property alias replaceEnter: mainStack.replaceEnter
    property alias replaceExit: mainStack.replaceExit

    property int rightPadding: 0
    property int topPadding: 0
    property int leftPadding: 0
    property int bottomPadding: 0

    readonly property Item currentItem: mycroftConnection.currentRow.currentItem

    //for delegates to access the view... eventually this could be come an attache dproperty
    function view() {
        return root;
    }

    function goBack() {
        //assume mainStack can only have a depth of 1 or 2
        if (mainStack.depth == 1) {
            return;
        }

        //current item is paginated and can we go back?
        if (mycroftConnection.currentRow.currentItem.hasOwnProperty("currentIndex") && mycroftConnection.currentRow.currentItem.currentIndex > 0) {
            mycroftConnection.currentRow.currentItem.currentIndex--;
            //reset the countdown
            mycroftConnection.currentRow.currentItem.userInteractingChanged();
        //we're in pageRow, flick back
        } else if (mycroftConnection.currentRow.currentIndex > 0) {
            mycroftConnection.currentRow.currentIndex--;
            //reset the countdown
            mycroftConnection.currentRow.currentItem.userInteractingChanged();
        //otherwise pop
        } else {
            mainStack.pop();
            popTimer.running = false;
            countdownAnim.running = false;
        }
    }

    StackView {
        id: mainStack
        anchors.fill: parent
        onBusyChanged: {
            if (busy) {
                return;
            }

            if (currentItem != row1) {
                row1.clear();
            }
            if (currentItem != row2) {
                row2.clear();
            }
            //if (depth < 2) {
            //    mycroftConnection.metadataType = [];
            //}
        }

    }

    //two copies to animate between them
    Kirigami.PageRow {
        id: row1
        visible: false
        //disable columns
        defaultColumnWidth: width
    }

    Kirigami.PageRow {
        id: row2
        visible: false
        //disable columns
        defaultColumnWidth: width
    }

    Component.onCompleted: {
        if (!mainStack.initialItem) {
            mainStack.initialItem = initialPlaceHolder;
        }
    }

    //this is to make the class work wether the user specifies an initialItem or not 
    Item {
        id: initialPlaceHolder
    }

    Mycroft.SkillLoader {
        id: skillLoader
    }

    Connections {
        id: mycroftConnection
        property var metadataType: []
        property Kirigami.PageRow currentRow: row1
        target: Mycroft.MycroftController

        function openSkillUi(type, data) {
            var _url = skillLoader.uiForMetadataType(type);
            if (!_url) {
                return;
            }

            // put in a row only stuff from the same skill, 
            // clear the old stuff otherwise
            // clear also if the skills requests so with "resetWorkflow"
            if (metadataType.length > 0 &&
                (type.split("/")[0] != metadataType[0].split("/")[0]
                 || data.resetWorkflow)) {
                mycroftConnection.currentRow = mycroftConnection.currentRow == row1 ? row2 : row1;
                if (mainStack.depth > 1) {
                    mainStack.replace(mycroftConnection.currentRow);
                } else {
                    mainStack.push(mycroftConnection.currentRow);
                }
                metadataType = [];
            }

            var found = false;
            for (var i = 0; i < mycroftConnection.metadataType.length; ++i) {
                var page = mycroftConnection.currentRow.get(i);
                var key;

                for (key in data) {
                    if (page.hasOwnProperty(key)) {
                        page[key] = data[key];
                    }
                }

                if (mycroftConnection.metadataType[i] == type) {
                    mycroftConnection.currentRow.currentIndex = i;
                    found = true;
                }
            }

            if (!found) {
                mycroftConnection.metadataType.push(type);
                mycroftConnection.currentRow.currentIndex = mycroftConnection.currentRow.depth - 1;
                mycroftConnection.currentRow.push(_url, data);
            }

            if (mainStack.depth < 2) {
                mainStack.push(mycroftConnection.currentRow);
            }

            popTimer.running = false;
            countdownAnim.running = false;
        }

        //These few lines are a cludge to make existing skills work that don't have metadata (yet)
        onFallbackTextRecieved: {
            console.log("Fallback", skill);
            var regex = /(.*)Skill*/;
            var found = skill.match(regex);
            if (found.length > 1) {
                openSkillUi(found[1].toLowerCase(), data);
            }
        }

        onStopped: {
            //explictly unset
            if (mainStack.depth > 1) {
                popTimer.running = false;
                countdownAnim.running = false;
                mainStack.pop(mainStack.initialItem);
                mainStack.metadataType = [];
            }
            return;
        }

        onSkillDataRecieved: {
            openSkillUi(data["type"], data);
        }

        onSpeakingChanged: {
            if (!Mycroft.MycroftController.speaking) {
                if (mycroftConnection.currentRow.depth > 0 && (!mycroftConnection.currentRow.currentItem.hasOwnProperty("graceTime") || (mycroftConnection.currentRow.currentItem.graceTime != Infinity && mycroftConnection.currentRow.currentItem.graceTime > 0))) {
                    popTimer.restart();
                    countdownAnim.restart();
                }
            }
        }
    }
    Connections {
        target: mycroftConnection.currentRow.currentItem
        onBackRequested: root.goBack();
        onUserInteractingChanged: {
            if (mycroftConnection.currentRow.currentItem.userInteracting) {
                popTimer.running = false;
                countdownAnim.running = false;
            } else if (!Mycroft.MycroftController.speaking && (!mycroftConnection.currentRow.currentItem.hasOwnProperty("graceTime") || (mycroftConnection.currentRow.currentItem.graceTime != Infinity && mycroftConnection.currentRow.currentItem.graceTime > 0))) {
                popTimer.restart();
                countdownAnim.restart();
            }
        }
    }

    Timer {
        id: popTimer
        interval: mycroftConnection.currentRow.currentItem && mycroftConnection.currentRow.currentItem.hasOwnProperty("graceTime") ? mycroftConnection.currentRow.currentItem.graceTime : 0
        onTriggered: {
            if (mainStack.depth > 1) {
                mainStack.pop(mainStack.initialItem);
                mycroftConnection.metadataType = [];
            }
        }
    }

    Rectangle {
        id: countdownScrollBar
        z: 999
        anchors {
            left: parent.left
            bottom: parent.bottom
        }
        height: Kirigami.Units.smallSpacing
        Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
        color: Kirigami.Theme.textColor
        width: 0
        opacity: countdownAnim.running ? 0.6 : 0
        Behavior on opacity {
            OpacityAnimator {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.InOutCubic
            }
        }

        PropertyAnimation {
            id: countdownAnim
            target: countdownScrollBar
            property: "width"
            from: parent.width
            to: 0
            duration: popTimer.interval
        }
    }
}
