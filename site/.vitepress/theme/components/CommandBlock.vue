<script setup lang="ts">
// A click-to-copy command box. The whole box is the button, so a reader can
// copy the install line without selecting it by hand; the label flips to a
// confirmation for a moment. Sits under the hero's download button: during
// the unnotarized beta the terminal install is the path with no Gatekeeper
// prompt, so `lead` says so right above it.
import { ref } from 'vue'

const props = defineProps<{
  command: string
  lead?: string
  note?: string
  copyLabel?: string
  copiedLabel?: string
}>()

const copied = ref(false)
let timer: ReturnType<typeof setTimeout> | undefined

const copy = async () => {
  try {
    await navigator.clipboard.writeText(props.command)
    copied.value = true
    clearTimeout(timer)
    timer = setTimeout(() => (copied.value = false), 1600)
  } catch {
    // Clipboard blocked (insecure context, denied permission): the command
    // is still visible and selectable, so there's nothing to recover — just
    // don't flash the confirmation.
  }
}
</script>

<template>
  <div class="kh-cmd">
    <span v-if="lead" class="kh-cmd-lead">{{ lead }}</span>
    <button
      type="button"
      class="kh-cmd-box"
      :aria-label="`${copyLabel ?? 'Copy'}: ${command}`"
      @click="copy"
    >
      <code>{{ command }}</code>
      <span class="kh-cmd-copy" :class="{ 'is-copied': copied }">
        {{ copied ? (copiedLabel ?? 'Copied') : (copyLabel ?? 'Copy') }}
      </span>
    </button>
    <span v-if="note" class="kh-cmd-note">{{ note }}</span>
  </div>
</template>
