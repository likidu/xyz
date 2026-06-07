#ifndef AUTHCLIENT_H
#define AUTHCLIENT_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QSslError>

class StorageManager;

// Native auth client for the official 小宇宙 API (send-code / login-with-sms).
// Mirrors the podin PodcastIndexClient pattern: single NAM + one in-flight reply,
// 15s timeout, per-reply ignoreSslErrors, status read from HttpStatusCodeAttribute,
// qjson body parsing. Tokens/profile persist via StorageManager. See docs/API_NOTES.md.
class AuthClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

public:
    explicit AuthClient(StorageManager *storage, QObject *parent = 0);

    bool busy() const;
    QString errorMessage() const;

    Q_INVOKABLE void sendCode(const QString &phone, const QString &areaCode);
    Q_INVOKABLE void login(const QString &phone, const QString &areaCode,
                           const QString &verifyCode);
    Q_INVOKABLE void logout();
    Q_INVOKABLE bool isLoggedIn() const;

signals:
    void busyChanged();
    void errorMessageChanged();
    void sendCodeSucceeded();
    void loginSucceeded();

private slots:
    void onReplyFinished();
    void onTimeout();
    void onSslErrors(const QList<QSslError> &errors);

private:
    enum RequestType { NoneRequest, SendCodeRequest, LoginRequest };

    void startPost(RequestType type, const QString &path, const QVariantMap &body);
    void abortActiveRequest();
    void setBusy(bool busy);
    void setErrorMessage(const QString &message);
    QString extractErrorDetail(const QByteArray &payload) const;

    StorageManager *m_storage;
    QNetworkAccessManager *m_nam;
    QNetworkReply *m_reply;
    QTimer m_timeout;
    bool m_busy;
    QString m_errorMessage;
    RequestType m_requestType;
    // login context, kept to persist alongside the response
    QString m_phone;
    QString m_areaCode;
};

#endif // AUTHCLIENT_H
