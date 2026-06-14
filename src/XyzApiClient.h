#ifndef XYZAPICLIENT_H
#define XYZAPICLIENT_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QSslError>

class StorageManager;

// Native content client for api.xiaoyuzhoufm.com (mirrors AuthClient's shape).
// Exposed to QML as the `xyzApi` context property.
class XyzApiClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QVariantList inboxItems READ inboxItems NOTIFY inboxLoaded)
    Q_PROPERTY(QVariantList subscriptions READ subscriptions NOTIFY subscriptionsLoaded)

public:
    explicit XyzApiClient(StorageManager *storage, QObject *parent = 0);

    bool busy() const;
    QString errorMessage() const;
    QVariantList inboxItems() const;
    QVariantList subscriptions() const;

    Q_INVOKABLE void fetchInbox();
    Q_INVOKABLE void fetchSubscriptions();

signals:
    void busyChanged();
    void errorMessageChanged();
    void inboxLoaded();
    void subscriptionsLoaded();
    void sessionExpired();

private slots:
    void onReplyFinished();
    void onTimeout();
    void onSslErrors(const QList<QSslError> &errors);

private:
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest };

    void startPost(RequestType type, const QString &path, const QVariantMap &body);
    void abortActiveRequest();
    void applyContentHeaders(QNetworkRequest &request);
    void setBusy(bool busy);
    void setErrorMessage(const QString &message);

    QVariantMap shapeInboxItem(const QVariantMap &item) const;
    QVariantMap shapeSubscription(const QVariantMap &item) const;
    QString pickImageUrl(const QVariantMap &image) const;
    QString relativeTime(const QString &iso) const;

    StorageManager *m_storage;
    QNetworkAccessManager *m_nam;
    QNetworkReply *m_reply;
    QTimer m_timeout;
    bool m_busy;
    QString m_errorMessage;
    RequestType m_requestType;
    QVariantList m_inboxItems;
    QVariantList m_subscriptions;
};

#endif // XYZAPICLIENT_H
