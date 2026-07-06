import { ref, shallowRef, onBeforeUnmount } from 'vue';
import { fetchIceServers, postDebugLog } from './api.js';
import { useSignaling } from './useSignaling.js';
import { mungeOpusFmtp } from './sdpMunge.js';

const VIDEO_CONSTRAINTS = {
  width: { ideal: 640 },
  height: { ideal: 360 },
  frameRate: { ideal: 24, max: 24 },
};

const STATS_INTERVAL_MS = 2500;
const DEBUG_REPORT_INTERVAL_MS = 10_000;
const VIDEO_MAX_BITRATE = 350_000;

export function useCall(roomId) {
  const localStream = shallowRef(null);
  const remoteStream = shallowRef(null);
  const peerStatus = ref('waiting'); // waiting | connected | peer-left | reconnecting
  const connectionState = ref('new');
  const isMuted = ref(false);
  const isCameraOff = ref(false);
  const stats = ref({ candidateType: null, protocol: null, outboundKbps: 0, inboundKbps: 0, packetLoss: null, rtt: null });

  let pc = null;
  let signaling = null;
  let iceServers = null;
  let polite = true;
  let politeAssigned = false;
  let makingOffer = false;
  let ignoreOffer = false;
  let relayOnly = false;
  let statsTimer = null;
  let debugTimer = null;
  let lastStats = null;

  // Builds a fresh RTCPeerConnection with all handlers and local tracks
  // wired up. Called once from start(), and again from the 'peer-left'
  // handler below: once the other side has fully left the room, the old
  // pc's ICE/SDP state has nothing left to talk to, and trying to nurse it
  // back to life (ICE restart, stale offers, politeness bookkeeping) is a
  // losing game — a rejoining peer always shows up with a brand-new
  // RTCPeerConnection of its own, so the cleanest way to meet it is with
  // one too.
  async function createPeerConnection() {
    if (pc) pc.close();

    pc = new RTCPeerConnection({
      iceServers,
      iceTransportPolicy: relayOnly ? 'relay' : 'all',
    });

    remoteStream.value = new MediaStream();
    pc.ontrack = (event) => {
      for (const track of event.streams[0]?.getTracks() ?? [event.track]) {
        remoteStream.value.addTrack(track);
      }
    };

    pc.oniceconnectionstatechange = () => {
      connectionState.value = pc.iceConnectionState;
      if (pc.iceConnectionState === 'connected' || pc.iceConnectionState === 'completed') {
        peerStatus.value = 'connected';
      } else if (pc.iceConnectionState === 'failed') {
        if (!relayOnly) {
          // A direct/srflx path didn't work out — rebuild the connection
          // forced to relay-only instead of just restarting ICE with the
          // same candidate policy that already failed.
          relayOnly = true;
          peerStatus.value = 'reconnecting';
          createPeerConnection().catch((err) => console.error('failed to fall back to relay', err));
        } else {
          restartIce();
        }
      } else if (pc.iceConnectionState === 'disconnected') {
        restartIce();
      }
    };

    pc.onicecandidate = ({ candidate }) => {
      if (candidate) signaling.send({ candidate });
    };

    pc.onnegotiationneeded = async () => {
      try {
        makingOffer = true;
        const offer = await pc.createOffer();
        offer.sdp = mungeOpusFmtp(offer.sdp);
        await pc.setLocalDescription(offer);
        signaling.send({ description: pc.localDescription });
      } catch (err) {
        console.error('negotiation failed', err);
      } finally {
        makingOffer = false;
      }
    };

    for (const track of localStream.value.getTracks()) {
      pc.addTrack(track, localStream.value);
    }
    await applyVideoBitrateLimit();
  }

  async function start() {
    localStream.value = await navigator.mediaDevices.getUserMedia({
      video: VIDEO_CONSTRAINTS,
      audio: true,
    });
    const [videoTrack] = localStream.value.getVideoTracks();
    if (videoTrack) videoTrack.contentHint = 'motion';

    ({ iceServers } = await fetchIceServers(roomId));

    // signaling must exist before createPeerConnection() below: 'negotiationneeded'
    // and ICE candidates fire asynchronously and call signaling.send(), and if
    // they fire before it's assigned, the event is lost and neither side ever
    // creates an offer.
    signaling = useSignaling(roomId);

    let hasConnectedBefore = false;
    signaling.events.addEventListener('open', () => {
      // A WS reconnect after a drop needs a fresh offer/answer exchange
      // since ICE state may be stale on one or both sides.
      if (hasConnectedBefore && pc && pc.signalingState !== 'closed') {
        pc.restartIce();
      }
      hasConnectedBefore = true;
    });

    signaling.events.addEventListener('joined', (event) => {
      // Only the very first join decides politeness. A WS reconnect (e.g.
      // after a network switch) re-triggers 'joined' with whatever peerCount
      // the room happens to have at that moment, which has nothing to do
      // with this client's original role — reassigning it here could flip
      // both peers to impolite (if the other side's role never changes),
      // and impolite/impolite means each side ignores the other's offer
      // during any collision, deadlocking the reconnect forever.
      if (politeAssigned) return;
      polite = event.detail.peerCount === 1;
      politeAssigned = true;
    });

    signaling.events.addEventListener('peer-left', () => {
      peerStatus.value = 'peer-left';
      // The old pc was talking to a peer that's now completely gone —
      // start fresh so we're in a clean 'stable' state, ready to accept
      // whatever offer the rejoining peer's own brand-new pc sends, rather
      // than juggling stale ICE state / a dangling local offer / politeness
      // edge cases on a connection with nothing left on the other end.
      polite = true;
      makingOffer = false;
      ignoreOffer = false;
      lastStats = null;
      createPeerConnection().catch((err) => console.error('failed to reset peer connection', err));
    });

    signaling.events.addEventListener('peer-joined', () => {
      peerStatus.value = 'waiting';
    });

    signaling.events.addEventListener('signal', async (event) => {
      const { description, candidate } = event.detail;
      try {
        if (description) {
          const offerCollision =
            description.type === 'offer' && (makingOffer || pc.signalingState !== 'stable');
          ignoreOffer = !polite && offerCollision;
          if (ignoreOffer) return;

          await pc.setRemoteDescription(description);
          if (description.type === 'offer') {
            const answer = await pc.createAnswer();
            answer.sdp = mungeOpusFmtp(answer.sdp);
            await pc.setLocalDescription(answer);
            signaling.send({ description: pc.localDescription });
          }
        } else if (candidate) {
          try {
            await pc.addIceCandidate(candidate);
          } catch (err) {
            if (!ignoreOffer) throw err;
          }
        }
      } catch (err) {
        console.error('signal handling failed', err);
      }
    });

    await createPeerConnection();

    startStatsPolling();
    startDebugReporting();
  }

  async function applyVideoBitrateLimit() {
    const sender = pc.getSenders().find((s) => s.track?.kind === 'video');
    if (!sender) return;
    const params = sender.getParameters();
    if (!params.encodings || params.encodings.length === 0) params.encodings = [{}];
    params.encodings[0].maxBitrate = VIDEO_MAX_BITRATE;
    params.encodings[0].degradationPreference = 'maintain-framerate';
    params.degradationPreference = 'maintain-framerate';
    await sender.setParameters(params);
  }

  function restartIce() {
    if (!pc || pc.signalingState === 'closed') return;
    peerStatus.value = 'reconnecting';
    pc.restartIce();
  }

  function toggleMute() {
    if (!localStream.value) return;
    isMuted.value = !isMuted.value;
    for (const track of localStream.value.getAudioTracks()) {
      track.enabled = !isMuted.value;
    }
  }

  function toggleCamera() {
    if (!localStream.value) return;
    isCameraOff.value = !isCameraOff.value;
    for (const track of localStream.value.getVideoTracks()) {
      track.enabled = !isCameraOff.value;
    }
  }

  function startStatsPolling() {
    statsTimer = setInterval(async () => {
      if (!pc) return;
      const report = await pc.getStats();
      let activePair = null;
      report.forEach((entry) => {
        if (entry.type === 'candidate-pair' && entry.nominated && entry.state === 'succeeded') {
          activePair = entry;
        }
      });
      if (!activePair) return;

      const localCandidate = report.get(activePair.localCandidateId);
      const remoteCandidate = report.get(activePair.remoteCandidateId);

      let outboundKbps = 0;
      let inboundKbps = 0;
      let packetLoss = null;
      report.forEach((entry) => {
        if (entry.type === 'outbound-rtp' && entry.kind === 'video') {
          if (lastStats?.outbound) {
            const bytesDelta = entry.bytesSent - lastStats.outbound.bytesSent;
            const timeDelta = (entry.timestamp - lastStats.outbound.timestamp) / 1000;
            outboundKbps = timeDelta > 0 ? Math.round((bytesDelta * 8) / timeDelta / 1000) : 0;
          }
          lastStats = { ...lastStats, outbound: entry };
        }
        if (entry.type === 'inbound-rtp' && entry.kind === 'video') {
          if (lastStats?.inbound) {
            const bytesDelta = entry.bytesReceived - lastStats.inbound.bytesReceived;
            const timeDelta = (entry.timestamp - lastStats.inbound.timestamp) / 1000;
            inboundKbps = timeDelta > 0 ? Math.round((bytesDelta * 8) / timeDelta / 1000) : 0;
          }
          if (entry.packetsLost != null && entry.packetsReceived != null) {
            const total = entry.packetsLost + entry.packetsReceived;
            packetLoss = total > 0 ? Math.round((entry.packetsLost / total) * 1000) / 10 : 0;
          }
          lastStats = { ...lastStats, inbound: entry };
        }
      });

      stats.value = {
        candidateType: localCandidate?.candidateType ?? null,
        protocol: localCandidate?.protocol ?? null,
        outboundKbps,
        inboundKbps,
        packetLoss,
        rtt: activePair.currentRoundTripTime != null ? Math.round(activePair.currentRoundTripTime * 1000) : null,
      };
    }, STATS_INTERVAL_MS);
  }

  // No visible debug UI — instead, periodically ship the same connection
  // stats to the server so the Iran side's call quality can be diagnosed
  // from server logs after the fact (see node-service/debugLog.js).
  function startDebugReporting() {
    debugTimer = setInterval(() => {
      postDebugLog(roomId, {
        peerStatus: peerStatus.value,
        connectionState: connectionState.value,
        relayOnly,
        ...stats.value,
      });
    }, DEBUG_REPORT_INTERVAL_MS);
  }

  function hangup() {
    clearInterval(statsTimer);
    clearInterval(debugTimer);
    signaling?.close();
    pc?.close();
    for (const track of localStream.value?.getTracks() ?? []) {
      track.stop();
    }
  }

  onBeforeUnmount(hangup);

  return {
    localStream,
    remoteStream,
    peerStatus,
    isMuted,
    isCameraOff,
    start,
    toggleMute,
    toggleCamera,
    hangup,
  };
}
