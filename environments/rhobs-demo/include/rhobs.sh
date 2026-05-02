rhobs_s3_bucket() {
  cat "$(_get_secret 'rhobs/s3_bucket_name')"
}
