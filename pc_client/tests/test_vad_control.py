import asyncio
from pathlib import Path

import pytest

from pc_client.ble_client import BleFaceSession
from pc_client.protocol import MessageType, Packet, PacketHeader, ProtocolError, decode_packet


@pytest.mark.parametrize("state", [False, True])
def test_vad_ack_before_write_returns(tmp_path: Path, state: bool) -> None:
    async def run() -> None:
        session = BleFaceSession("test", event_database=tmp_path / "events.db")

        class Client:
            is_connected = True

            async def write_gatt_char(self, _: str, data: bytes, *, response: bool) -> None:
                request = decode_packet(data)
                assert request.header.message_type is MessageType.VAD_SET
                assert request.payload == bytes([state])
                reply = Packet(PacketHeader(message_type=MessageType.VAD_STATUS,
                                            request_id=request.header.request_id), bytes([state]))
                session._notification(None, bytearray(reply.encode()))

        session.client = Client()
        try:
            assert await session.set_vad(state) is state
            assert not session._vad_pending
        finally:
            session.close()
    asyncio.run(run())


@pytest.mark.parametrize("reply_type,payload", [(MessageType.ERROR, b"\x04\x00"),
                                               (MessageType.VAD_STATUS, b"\x02"),
                                               (MessageType.VAD_STATUS, b"")])
def test_vad_invalid_reply_fails(tmp_path: Path, reply_type: MessageType, payload: bytes) -> None:
    async def run() -> None:
        session = BleFaceSession("test", event_database=tmp_path / "events.db")

        class Client:
            is_connected = True

            async def write_gatt_char(self, _: str, data: bytes, *, response: bool) -> None:
                request = decode_packet(data)
                reply = Packet(PacketHeader(message_type=reply_type,
                                            request_id=request.header.request_id), payload)
                session._notification(None, bytearray(reply.encode()))

        session.client = Client()
        try:
            with pytest.raises(ProtocolError):
                await session.set_vad(False)
            assert not session._vad_pending
        finally:
            session.close()
    asyncio.run(run())
