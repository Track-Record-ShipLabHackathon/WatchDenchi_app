/// Public base URL supplied by the developer or distribution build.
const watchDenchiApiBaseUrl = String.fromEnvironment(
  'WATCHDENCHI_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8080',
);
