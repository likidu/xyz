TEMPLATE = app
TARGET = Xyz
VERSION = 0.1.0

# Qt 4.x modules
QT += core gui network declarative sql
CONFIG += mobility
MOBILITY += multimedia
symbian:LIBS += -lhal
symbian:LIBS += -lefsrv     # RFs::Volume for the downloads storage meter

CONFIG -= debug_and_release
CONFIG(debug, debug|release) {
    CONFIG += console
    DEFINES += XYZ_DEBUG
}

# Place all build artifacts inside build directory
DESTDIR = $$OUT_PWD
OBJECTS_DIR = $$OUT_PWD/obj
MOC_DIR = $$OUT_PWD/moc
RCC_DIR = $$OUT_PWD/rcc
UI_DIR = $$OUT_PWD/ui

INCLUDEPATH += src

# Vendored qjson (Qt 4 has no QJsonDocument); compiled in statically.
include($$PWD/lib/qjson/qjson.pri)
DEFINES += QJSON_STATIC

symbian {
    # Self-signed app UID (range 0xE0000000-0xEFFFFFFF). Set explicitly so the
    # identity is stable instead of derived from TARGET; keep emptyfile.path below
    # (the /private/<uid> data-cage dir) in sync with this value.
    TARGET.UID3 = 0xE7B5C0DE

    TARGET.EPOCHEAPSIZE = 0x020000 0x2000000
    # Required capabilities for network streaming + local storage
    TARGET.CAPABILITY += NetworkServices ReadUserData WriteUserData UserEnvironment

    # Hardware volume keys come through the RemCon framework, not key events.
    LIBS += -lremconcoreapi -lremconinterfacebase
    SOURCES += src/VolumeKeyCapturer.cpp
    HEADERS += src/VolumeKeyCapturer.h

    # Note: SQLite driver is built into QtSql.dll on Symbian, no separate plugin deployment needed

    # Create the private data directory during installation so the app can write its database
    DEPLOYMENT.installer_header = 0x2002CCCF

    # Deploy an empty placeholder file to create the private directory
    emptyfile.sources = data/.placeholder
    emptyfile.path = /private/e7b5c0de
    DEPLOYMENT += emptyfile

    # Pigler Notifications API (vendored from github.com/piglerorg/pigler).
    # Status-panel notifications via the user-installed Pigler.sis server.
    DEFINES += PIGLER_API_ANNA_RECONNECT
    INCLUDEPATH += src/pigler
    LIBS += -lrandom -laknnotify
    SOURCES += src/pigler/QPiglerAPI.cpp \
               src/pigler/PiglerAPI.cpp \
               src/pigler/PiglerTapServer.cpp
    HEADERS += src/pigler/QPiglerAPI.h \
               src/pigler/PiglerAPI.h \
               src/pigler/PiglerTapServer.h \
               src/pigler/PiglerProtocol.h
}

SOURCES += \
    src/main.cpp \
    src/MemoryMonitor.cpp \
    src/TlsChecker.cpp \
    src/StorageManager.cpp \
    src/AudioEngine.cpp \
    src/AuthClient.cpp \
    src/XyzApiClient.cpp \
    src/EpisodeDownloader.cpp \
    src/PlayerController.cpp \
    src/DownloadRegistry.cpp \
    src/NowPlayingNotifier.cpp

HEADERS += \
    src/MemoryMonitor.h \
    src/TlsChecker.h \
    src/AppConfig.h \
    src/StorageManager.h \
    src/AudioEngine.h \
    src/AuthClient.h \
    src/XyzApiClient.h \
    src/EpisodeDownloader.h \
    src/PlayerController.h \
    src/DownloadRegistry.h \
    src/NowPlayingNotifier.h

RESOURCES += \
    qml/qml.qrc

OTHER_FILES += \
    qml/AppWindow.qml \
    qml/SelfTestPage.qml \
    qml/MemoryBar.qml \
    qml/XyzPageStackWindow.qml \
    qml/BelleHeader.qml \
    qml/BelleTabBar.qml \
    qml/LoginPage.qml \
    qml/VerifyCodePage.qml \
    qml/HomePage.qml \
    qml/UpdatesPage.qml \
    qml/SubscriptionsPage.qml \
    qml/EpisodePage.qml \
    qml/DownloadsPage.qml \
    qml/NowPlayingPage.qml \
    qml/MiniPlayer.qml \
    qml/js/Theme.js

