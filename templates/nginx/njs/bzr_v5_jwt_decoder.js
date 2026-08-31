function unauthorized(r, reason) {
  r.return(401, JSON.stringify({ reason: reason, result: null, status: 401 }));
  return 0;
}

function verify(r) {
  // TODO: get this secret from env
  var secret = '{{JWT_TOKEN}}';

  // Every early return must go through unauthorized(). An uncaught exception in a
  // js_set handler leaves the variable empty and nginx proxies the request onward,
  // so a throw here reads as "allowed" rather than "denied".
  var auth = r.headersIn.Authorization;
  if (!auth || auth.slice(0, 7).toLowerCase() !== 'bearer ') {
    return unauthorized(r, 'unauthorized');
  }

  var jwtB64 = auth.slice(7).split('.');
  if (jwtB64.length != 3) {
    return unauthorized(r, 'unauthorized');
  }

  var headerB64 = jwtB64[0];
  var payloadB64 = jwtB64[1];
  var signatureB64 = jwtB64[2];

  var hmac256 = require('crypto').createHmac('sha256', secret);

  var seed = [headerB64, payloadB64].join('.');

  var verifiedSignature = hmac256.update(seed).digest('base64');

  verifiedSignature = verifiedSignature.replace(/\+/g, '-');
  verifiedSignature = verifiedSignature.replace(/\//g, '_');
  verifiedSignature = verifiedSignature.replace(/=/g, '');

  if (verifiedSignature != signatureB64) {
    return unauthorized(r, 'unauthorized');
  }

  var userString = Buffer.from(payloadB64, 'base64').toString('utf-8');
  var userJSON = JSON.parse(userString);

  var currentTime = Math.floor(Date.now() / 1000);
  if (currentTime > userJSON.exp) {
    return unauthorized(r, 'token expired');
  }

  return userString;
}

export default { verify }
