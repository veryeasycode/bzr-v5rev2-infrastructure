const { loadEnvFile } = require('node:process');
loadEnvFile(); // Loads from .env by default
try {
  const admin_db = db.getSiblingDB('admin');
  admin_db.auth(process.env.MONGO_USERNAME , process.env.MONGO_PASSWORD);
  let rs_loop = 2;
  while (rs_loop --) {
    try {
      rs.status();
      console.log(`${process.env.MONGO_REPLICA_SET} has been initiated.`);
      break;
    } catch (rs_err) {
      console.log(rs_err.message);
      if(rs_err.message == 'no replset config has been received') {
        rs.initiate();
      }
    }
  }
} catch (err) {
  console.log(err.message);
  quit(1);
}