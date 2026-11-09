const apiUrl = process.env.STUDY_NOTES_API_URL ?? "http://127.0.0.1:8765";

export default {
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: `${apiUrl}/api/:path*`
      }
    ];
  }
};
