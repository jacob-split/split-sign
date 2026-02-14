<template>
  <svg
    height="40"
    width="40"
    viewBox="0 0 200 200"
    xmlns="http://www.w3.org/2000/svg"
  >
    <defs>
      <style>
        .split-mark { stroke: currentColor; stroke-width: 6; fill: none; stroke-linecap: round; }
      </style>
    </defs>
    
    <line x1="55" y1="40" x2="55" y2="120" class="split-mark"/>
    <line x1="145" y1="40" x2="145" y2="120" class="split-mark"/>
    <line x1="55" y1="80" x2="145" y2="80" class="split-mark"/>
  </svg>
</template>

<script>
export default {
  name: 'ProjectLogo'
}
</script>
