#include <NimBLEDevice.h>
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
static volatile uint8_t links = 0;

class ServerCb : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, ble_gap_conn_desc* d) override {
    links++;
    s->updateConnParams(d->conn_handle, 6, 12, 0, 400);
    NimBLEDevice::startAdvertising();  // allow a second device (phone + tablet)
  }
  void onDisconnect(NimBLEServer*) override {
    if (links) links--;
    mtu = 23;
  }
  void onMTUChange(uint16_t m, ble_gap_conn_desc*) override { mtu = m; }
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
  svc->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(PROOT_SVC);
  adv->setScanResponse(true);
  adv->start();
}

void stop() {
  if (!server) return;
  NimBLEDevice::deinit(true);
  server = nullptr;
  tx = nullptr;
  links = 0;
}

bool connected() { return links > 0; }

void send(const String& json) {
  if (!tx || !links) return;
  size_t chunk = max(20, (int)mtu - 4);
  const uint8_t* p = (const uint8_t*)json.c_str();
  size_t left = json.length(), off = 0;
  uint8_t pkt[520];
  while (left || off == 0) {
    size_t n = min(left, chunk);
    pkt[0] = (off == 0 ? 0x40 : 0) | (n == left ? 0x20 : 0);
    memcpy(pkt + 1, p + off, n);
    tx->setValue(pkt, n + 1);
    tx->notify();
    off += n;
    left -= n;
    if (left) delay(4);  // give the controller room to drain its buffers
    if (!n) break;
  }
}

}  // namespace ble
