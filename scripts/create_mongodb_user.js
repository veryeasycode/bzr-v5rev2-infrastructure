const { loadEnvFile } = require('node:process');
loadEnvFile(); // Loads from .env by default
const admin_db = db.getSiblingDB('admin');
admin_db.createUser({ user: process.env.MONGO_USERNAME, pwd: process.env.MONGO_PASSWORD, roles: [{ role: 'root', db: 'admin'} ]});
console.log(`Create ${process.env.MONGO_USERNAME} as default user.`);