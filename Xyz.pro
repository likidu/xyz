TEMPLATE = app
TARGET = Xyz
VERSION = 0.1.0

# Qt 4.x modules
QT += core gui network declarative sql
CONFIG += mobility
MOBILITY += multimedia
symbian:LIBS += -lhal

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
    TARGET.EPOCHEAPSIZE = 0x020000 0x2000000
    # Required capabilities for network streaming + local storage
    TARGET.CAPABILITY += NetworkServices ReadUserData WriteUserData UserEnvironment

    # Note: SQLite driver is built into QtSql.dll on Symbian, no separate plugin deployment needed

    # Create the private data directory during installation so the app can write its database
    DEPLOYMENT.installer_header = 0x2002CCCF

    # Deploy an empty placeholder file to create the private directory
    emptyfile.sources = data/.placeholder
    emptyfile.path = /private/e7654321
    DEPLOYMENT += emptyfile
}

SOURCES += \
    src/main.cpp \
    src/MemoryMonitor.cpp \
    src/TlsChecker.cpp \
    src/StorageManager.cpp \
    src/AudioEngine.cpp \
    src/AuthClient.cpp \
    src/XyzApiClient.cpp

HEADERS += \
    src/MemoryMonitor.h \
    src/TlsChecker.h \
    src/AppConfig.h \
    src/StorageManager.h \
    src/AudioEngine.h \
    src/AuthClient.h \
    src/XyzApiClient.h

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
    qml/js/Theme.js

