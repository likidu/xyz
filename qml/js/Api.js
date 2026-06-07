// 小宇宙 official API — auth calls. See docs/API_NOTES.md.
// Constant spoof headers (User-Agent etc.) are injected in C++ (SslIgnoringNam);
// QML XHR only sets Content-Type here.
//
// Qt 4.7 quirk: for HTTP error responses (4xx/5xx) the QML XMLHttpRequest resets
// status to 0 at readyState DONE. We capture the last non-zero status (and body)
// seen during HEADERS_RECEIVED/LOADING so error handling can report the real code.
.pragma library

var AUTH_BASE = "https://podcaster-api.xiaoyuzhoufm.com";

// callback(ok, errorMessage)
function sendCode(phone, areaCode, callback) {
    _post(AUTH_BASE + "/v1/auth/send-code",
          { mobilePhoneNumber: phone, areaCode: areaCode },
          function (xhr, status, body) {
              if (status >= 200 && status < 300) {
                  callback(true, "");
              } else {
                  callback(false, _errorMessage(status, body));
              }
          });
}

// callback(ok, errorMessage, user, accessToken, refreshToken)
function login(phone, areaCode, verifyCode, callback) {
    _post(AUTH_BASE + "/v1/auth/login-with-sms",
          { areaCode: areaCode, verifyCode: verifyCode, mobilePhoneNumber: phone },
          function (xhr, status, body) {
              if (status < 200 || status >= 300) {
                  callback(false, _errorMessage(status, body), null, "", "");
                  return;
              }
              var accessToken = xhr.getResponseHeader("x-jike-access-token");
              var refreshToken = xhr.getResponseHeader("x-jike-refresh-token");
              if (!accessToken) {
                  callback(false, "No token in response", null, "", "");
                  return;
              }
              var user = null;
              try {
                  var parsed = JSON.parse(body);
                  // Official shape: { data: { user: {...} } }; be lenient.
                  if (parsed.data && parsed.data.user) {
                      user = parsed.data.user;
                  } else if (parsed.data) {
                      user = parsed.data;
                  } else {
                      user = parsed;
                  }
              } catch (e) {
                  // profile parse failure is non-fatal; tokens are what matter
              }
              callback(true, "", user, accessToken, refreshToken ? refreshToken : "");
          });
}

function _post(url, bodyObj, done) {
    var xhr = new XMLHttpRequest();
    var lastStatus = 0;
    var lastBody = "";
    xhr.open("POST", url);
    xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");
    xhr.setRequestHeader("Accept", "application/json, text/plain, */*");
    xhr.onreadystatechange = function () {
        if (xhr.status && xhr.status !== 0) {
            lastStatus = xhr.status;
        }
        if (xhr.responseText && xhr.responseText.length > 0) {
            lastBody = xhr.responseText;
        }
        if (xhr.readyState === XMLHttpRequest.DONE) {
            done(xhr, lastStatus, lastBody);
        }
    };
    xhr.send(JSON.stringify(bodyObj));
}

function _errorMessage(status, body) {
    try {
        var parsed = JSON.parse(body);
        if (parsed.toast) return parsed.toast;
        if (parsed.msg) return parsed.msg;
        if (parsed.message) return parsed.message;
    } catch (e) {
        // not JSON — fall through
    }
    if (status === 0) {
        return "Network error";
    }
    return "Request failed (" + status + ")";
}
