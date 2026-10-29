#include <NimBLEDevice.h>
#include <atomic>
#include <vector>
#include "comms.h"

// GATT: one service with an RX (write) and TX (notify) characteristic. Every
// packet starts with a header byte: bit7 = binary payload, bit6 = first packet,
// bit5 = last packet. Long messages span several packets.
#define PROOT_SVC "7f3e0001-4a2b-4d7e-9c1a-70726f6f7401"
#define PROOT_RX "7f3e0002-4a2b-4d7e-9c1a-70726f6f7401"
#define PROOT_TX "7f3e0003-4a2b-4d7e-9c1a-70726f6f7401"

namespace ble {

static NimBLEServer* server = nullptr;
static NimBLECharacteristic* tx = nullptr;
static std::vector<uint8_t> rxBuf;
static bool rxBinary = false;
static volatile uint16_t mtu = 23;
static std::atomic<uint8_t> links{0};
// Connections subscribed to TX notifications (BLE_HS_CONN_HANDLE_NONE = free slot).
static volatile uint16_t subs[2] = {BLE_HS_CONN_HANDLE_NONE, BLE_HS_CONN_HANDLE_NONE};

static void setSub(uint16_t conn, bool on) {
  for (auto& s : subs)
    if (s == conn) s = BLE_HS_CONN_HANDLE_NONE;
  if (!on) return;
  for (auto& s : subs)
    if (s == BLE_HS_CONN_HANDLE_NONE) {
      s = conn;
      return;
    }
}

class ServerCb : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, ble_gap_conn_desc* d) override {
    links++;
    Serial.printf("[ble] connected, heap=%u\n", (unsigned)ESP.getFreeHeap());
    // Within Apple's accessory guidelines: 15-30 ms interval, 4 s supervision timeout.
    s->updateConnParams(d->conn_handle, 12, 24, 0, 400);
    NimBLEDevice::startAdvertising();  // allow a second device (phone + tablet)
  }
  void onDisconnect(NimBLEServer*, ble_gap_conn_desc* d) override {
    if (links) links--;
    setSub(d->conn_handle, false);
    Serial.printf("[ble] disconnected, heap=%u\n", (unsigned)ESP.getFreeHeap());
    mtu = 23;
  }
  void onMTUChange(uint16_t m, ble_gap_conn_desc*) override {
    mtu = m;
    Serial.printf("[ble] mtu %u\n", m);
  }
};

class TxCb : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic*, ble_gap_conn_desc* d, uint16_t value) override { setSub(d->conn_handle, value != 0); }
};

class RxCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    NimBLEAttValue v = c->getValue();
    if (v.length() < 1) return;
    uint8_t h = v.data()[0];
    if (h & 0x40) {
      rxBuf.clear();
      rxBinary = h & 0x80;
    }
    if (rxBuf.size() + v.length() > 16384) {
      rxBuf.clear();
      return;
    }
    rxBuf.insert(rxBuf.end(), v.data() + 1, v.data() + v.length());
    if (h & 0x20) {
      comms::push(comms::Src::Ble, 0, rxBinary, rxBuf.data(), rxBuf.size());
      rxBuf.clear();
    }
  }
};

void begin(const char* name) {
  NimBLEDevice::init(name);
  NimBLEDevice::setMTU(517);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCb());
  NimBLEService* svc = server->createService(PROOT_SVC);
  NimBLECharacteristic* rx = svc->createCharacteristic(PROOT_RX, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  rx->setCallbacks(new RxCb());
  tx = svc->createCharacteristic(PROOT_TX, NIMBLE_PROPERTY::NOTIFY);
  tx->setCallbacks(new TxCb());
  svc->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(PROOT_SVC);
  adv->setScanResponse(true);
  adv->start();
  Serial.printf("[ble] advertising as %s, heap=%u\n", name, (unsigned)ESP.getFreeHeap());
}

void stop() {
  if (!server) return;
  NimBLEDevice::deinit(true);
  server = nullptr;
  tx = nullptr;
  links = 0;
}

bool connected() { return links > 0; }

// Sends one notification, waiting while NimBLE's buffer pool is full instead of
// dropping the packet (NimBLECharacteristic::notify() ignores that error).
static bool notifyPacket(uint16_t conn, const uint8_t* data, size_t len) {
  for (int attempt = 0; attempt < 200; attempt++) {
    os_mbuf* om = ble_hs_mbuf_from_flat(data, len);
    if (om) {
      int rc = ble_gattc_notify_custom(conn, tx->getHandle(), om);  // consumes om
      if (rc == 0) return true;
      if (rc != BLE_HS_ENOMEM && rc != BLE_HS_EBUSY) return false;
    }
    delay(2);
  }
  return false;
}

void send(const String& json) {
  if (!tx || !links) return;
  // Small packets fit one mbuf each, so a burst can't exhaust the pool mid-message.
  size_t chunk = constrain((int)mtu - 4, 20, 200);
  const uint8_t* p = (const uint8_t*)json.c_str();
  uint8_t pkt[208];
  for (uint16_t conn : subs) {
    if (conn == BLE_HS_CONN_HANDLE_NONE) continue;
    size_t left = json.length(), off = 0;
    do {
      size_t n = min(left, chunk);
      pkt[0] = (off == 0 ? 0x40 : 0) | (n == left ? 0x20 : 0);
      memcpy(pkt + 1, p + off, n);
      if (!notifyPacket(conn, pkt, n + 1)) break;
      off += n;
      left -= n;
    } while (left);
  }
}

}  // namespace ble
