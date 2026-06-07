#include "AuthClient.h"
#include "StorageManager.h"

#include <QtCore/QByteArray>
#include <QtCore/QStringList>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>
#include <QtCore/QVariant>
#include <QtCore/QVariantMap>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslSocket>

#include "parser.h"
#include "serializer.h"

namespace {

QByteArray authBase()
{
    const QByteArray override = qgetenv("XYZ_AUTH_BASE");
    if (!override.isEmpty()) {
        return override;
    }
    return QByteArray("https://podcaster-api.xiaoyuzhoufm.com");
}

// Browser-spoof headers the web podcaster portal expects (see docs/API_NOTES.md).
void applyAuthHeaders(QNetworkRequest &request)
{
    request.setRawHeader("Content-Type", "application/json;charset=UTF-8");
    request.setRawHeader("Accept", "application/json, text/plain, */*");
    request.setRawHeader("Accept-Language",
                         "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6");
    request.setRawHeader("Origin", "https://podcaster.xiaoyuzhoufm.com");
    request.setRawHeader("Referer", "https://podcaster.xiaoyuzhoufm.com/");
    request.setRawHeader("User-Agent",
                         "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                         "AppleWebKit/537.36 (KHTML, like Gecko) "
                         "Chrome/146.0.0.0 Safari/537.36 Edg/146.0.0.0");
}

// Pull the user profile out of the login body, tolerating shape variations:
// { data: { user: {...} } } | { data: {...} } | {...}.
QVariantMap extractUser(const QVariant &root)
{
    const QVariantMap top = root.toMap();
    const QVariant dataVal = top.value(QString::fromLatin1("data"));
    if (dataVal.isValid()) {
        const QVariantMap data = dataVal.toMap();
        const QVariant userVal = data.value(QString::fromLatin1("user"));
        if (userVal.isValid()) {
            return userVal.toMap();
        }
        if (!data.isEmpty()) {
            return data;
        }
    }
    return top;
}

} // namespace

AuthClient::AuthClient(StorageManager *storage, QObject *parent)
    : QObject(parent)
    , m_storage(storage)
    , m_nam(new QNetworkAccessManager(this))
    , m_reply(0)
    , m_busy(false)
    , m_requestType(NoneRequest)
{
    m_timeout.setSingleShot(true);
    connect(&m_timeout, SIGNAL(timeout()), this, SLOT(onTimeout()));
}

bool AuthClient::busy() const
{
    return m_busy;
}

QString AuthClient::errorMessage() const
{
    return m_errorMessage;
}

bool AuthClient::isLoggedIn() const
{
    return m_storage && !m_storage->value(QLatin1String("auth.accessToken")).isEmpty();
}

void AuthClient::sendCode(const QString &phone, const QString &areaCode)
{
    QVariantMap body;
    body.insert(QString::fromLatin1("mobilePhoneNumber"), phone);
    body.insert(QString::fromLatin1("areaCode"), areaCode);
    startPost(SendCodeRequest, QString::fromLatin1("/v1/auth/send-code"), body);
}

void AuthClient::login(const QString &phone, const QString &areaCode,
                       const QString &verifyCode)
{
    m_phone = phone;
    m_areaCode = areaCode;

    QVariantMap body;
    body.insert(QString::fromLatin1("areaCode"), areaCode);
    body.insert(QString::fromLatin1("verifyCode"), verifyCode);
    body.insert(QString::fromLatin1("mobilePhoneNumber"), phone);
    startPost(LoginRequest, QString::fromLatin1("/v1/auth/login-with-sms"), body);
}

void AuthClient::logout()
{
    if (!m_storage) {
        return;
    }
    m_storage->setValue(QLatin1String("auth.accessToken"), QString());
    m_storage->setValue(QLatin1String("auth.refreshToken"), QString());
    m_storage->setValue(QLatin1String("auth.uid"), QString());
    m_storage->setValue(QLatin1String("auth.nickname"), QString());
    m_storage->setValue(QLatin1String("auth.phone"), QString());
}

void AuthClient::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    emit busyChanged();
}

void AuthClient::setErrorMessage(const QString &message)
{
    if (m_errorMessage == message) {
        return;
    }
    m_errorMessage = message;
    emit errorMessageChanged();
}

void AuthClient::startPost(RequestType type, const QString &path, const QVariantMap &body)
{
    abortActiveRequest();
    setErrorMessage(QString());
    setBusy(true);
    m_requestType = type;

    if (!QSslSocket::supportsSsl()) {
        setErrorMessage(QString::fromLatin1("SSL not supported at runtime."));
        setBusy(false);
        m_requestType = NoneRequest;
        return;
    }

    const QUrl url(QString::fromLatin1(authBase()) + path);
    QNetworkRequest request(url);
    applyAuthHeaders(request);

    QJson::Serializer serializer;
    const QByteArray payload = serializer.serialize(body);

    m_reply = m_nam->post(request, payload);
    connect(m_reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    connect(m_reply, SIGNAL(sslErrors(const QList<QSslError> &)),
            this, SLOT(onSslErrors(const QList<QSslError> &)));
    m_timeout.start(15000);
}

void AuthClient::abortActiveRequest()
{
    if (!m_reply) {
        return;
    }
    disconnect(m_reply, 0, this, 0);
    m_reply->abort();
    m_reply->deleteLater();
    m_reply = 0;
    m_timeout.stop();
}

void AuthClient::onReplyFinished()
{
    m_timeout.stop();

    if (!m_reply) {
        setBusy(false);
        return;
    }

    QNetworkReply *reply = m_reply;
    m_reply = 0;
    const RequestType type = m_requestType;
    m_requestType = NoneRequest;

    const QByteArray payload = reply->readAll();
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray accessToken = reply->rawHeader("x-jike-access-token");
    const QByteArray refreshToken = reply->rawHeader("x-jike-refresh-token");
    reply->deleteLater();

    if (statusCode < 200 || statusCode >= 300) {
        const QString detail = extractErrorDetail(payload);
        if (!detail.isEmpty()) {
            setErrorMessage(detail);
        } else if (statusCode == 0) {
            setErrorMessage(QString::fromLatin1("Network error"));
        } else {
            setErrorMessage(QString::fromLatin1("Request failed (%1)").arg(statusCode));
        }
        setBusy(false);
        return;
    }

    if (type == SendCodeRequest) {
        setBusy(false);
        emit sendCodeSucceeded();
        return;
    }

    // LoginRequest
    if (accessToken.isEmpty()) {
        setErrorMessage(QString::fromLatin1("No token in response"));
        setBusy(false);
        return;
    }

    QString nickname;
    QString uid;
    QJson::Parser parser;
    bool ok = false;
    const QVariant root = parser.parse(payload, &ok);
    if (ok) {
        const QVariantMap user = extractUser(root);
        nickname = user.value(QString::fromLatin1("nickname")).toString();
        uid = user.value(QString::fromLatin1("uid")).toString();
    }

    if (m_storage) {
        m_storage->setValue(QLatin1String("auth.accessToken"), QString::fromUtf8(accessToken));
        m_storage->setValue(QLatin1String("auth.refreshToken"), QString::fromUtf8(refreshToken));
        m_storage->setValue(QLatin1String("auth.areaCode"), m_areaCode);
        m_storage->setValue(QLatin1String("auth.phone"), m_phone);
        m_storage->setValue(QLatin1String("auth.uid"), uid);
        m_storage->setValue(QLatin1String("auth.nickname"), nickname);
    }

    setBusy(false);
    emit loginSucceeded();
}

void AuthClient::onTimeout()
{
    abortActiveRequest();
    m_requestType = NoneRequest;
    setErrorMessage(QString::fromLatin1("Request timed out."));
    setBusy(false);
}

void AuthClient::onSslErrors(const QList<QSslError> &errors)
{
    if (!m_reply) {
        return;
    }

    QStringList messages;
    for (int i = 0; i < errors.size(); ++i) {
        messages.append(errors.at(i).errorString());
    }
    QTextStream ts(stdout);
    ts << "AuthClient SSL errors: " << messages.join(QString::fromLatin1("; ")) << '\n';
    ts.flush();

    // Symbian's CA store is stale; ignore SSL errors (same stance as the rest of the app).
    m_reply->ignoreSslErrors();
}

QString AuthClient::extractErrorDetail(const QByteArray &payload) const
{
    if (payload.isEmpty()) {
        return QString();
    }
    QJson::Parser parser;
    bool ok = false;
    const QVariant root = parser.parse(payload, &ok);
    if (!ok) {
        return QString();
    }
    const QVariantMap map = root.toMap();
    QStringList keys;
    keys << QString::fromLatin1("toast") << QString::fromLatin1("msg")
         << QString::fromLatin1("message");
    for (int i = 0; i < keys.size(); ++i) {
        const QString value = map.value(keys.at(i)).toString();
        if (!value.isEmpty()) {
            return value;
        }
    }
    return QString();
}
