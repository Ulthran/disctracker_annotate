<script setup lang="ts">
const repoUrl = 'https://github.com/Ulthran/ctbus_site/tree/master/frontend';
</script>

<template>
  <section class="hero">
    <h1>Disctracker Annotate</h1>
    <p>
      This is a starter Vue single-page application ready to be deployed behind an
      AWS S3 bucket and CloudFront distribution managed with Terraform.
    </p>
    <p>
      The structure mirrors the approach used in
      <a :href="repoUrl" target="_blank" rel="noreferrer">the ctbus_site frontend</a>
      while staying intentionally lightweight so we can iterate quickly.
    </p>
  </section>
</template>

<style scoped>
.hero {
  max-width: 720px;
  padding: 2.5rem;
  background: white;
  border-radius: 1rem;
  box-shadow: 0 20px 40px rgba(15, 23, 42, 0.15);
}

.hero h1 {
  margin-top: 0;
  margin-bottom: 1rem;
  font-size: clamp(2.5rem, 5vw, 3.5rem);
}

.hero p {
  margin: 0 0 1rem;
  font-size: 1.1rem;
  color: #334155;
}

.hero a {
  color: #2563eb;
  text-decoration: none;
  font-weight: 600;
}

.hero a:hover,
.hero a:focus {
  text-decoration: underline;
}
</style>
