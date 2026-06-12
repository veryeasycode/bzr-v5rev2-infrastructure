function verify(r) {
  // TODO: get this secret from env
  var secret = '{{JWT_TOKEN}}';

  var jwtB64 = r.headersIn.Authorization.slice(7).split('.');

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
    r.return(401, JSON.stringify({ reason: 'unauthorized', result: null, status: 401 }));
    return 0;
  }

  var userString = Buffer.from(payloadB64, 'base64').toString('utf-8');
  var userJSON = JSON.parse(userString);

  var currentTime = Math.floor(Date.now() / 1000);
  if (currentTime > userJSON.exp) {
    r.return(401, JSON.stringify({ reason: 'token expired', result: null, status: 401 }));
    return 0;
  }

  return userString;
}

export default { verify }