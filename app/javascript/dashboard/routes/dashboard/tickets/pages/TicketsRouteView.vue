<template>
  <!--
    The workspace's shell. Nothing is kept alive on purpose: the list's whole state lives in the URL, so
    coming back from a case re-reads it -- and re-reads the case that was just edited, which a cached page
    would not.
  -->
  <div class="flex flex-col flex-1 h-full m-0 overflow-hidden bg-n-surface-1">
    <RouterView />
  </div>
</template>
