<template>
  <!--
    The portal's shell. Nothing is kept alive on purpose: a ticket that was just replied to must be re-read
    when the customer comes back to the list, and a cached page would show the state before the reply.
  -->
  <div class="flex flex-col flex-1 h-full m-0 overflow-hidden bg-n-surface-1">
    <RouterView />
  </div>
</template>
