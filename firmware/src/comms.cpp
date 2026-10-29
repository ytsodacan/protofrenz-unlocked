#include "comms.h"

namespace comms {

static QueueHandle_t queue;

void begin() { queue = xQueueCreate(12, sizeof(Msg)); }

bool push(Src src, uint32_t client, bool binary, const uint8_t* data, size_t len) {
  Msg m{src, client, binary, len, (uint8_t*)malloc(len + 1)};
  if (!m.data) return false;
  memcpy(m.data, data, len);
  m.data[len] = 0;  // JSON parsers get a terminated string
  if (xQueueSend(queue, &m, pdMS_TO_TICKS(20)) != pdTRUE) {
    free(m.data);
    return false;
  }
  return true;
}

bool pop(Msg& m) { return xQueueReceive(queue, &m, 0) == pdTRUE; }

void reply(Src src, uint32_t client, const String& json) {
  if (src == Src::Ws) net::send(client, json);
  else ble::send(json);
}

void broadcast(const String& json) {
  net::broadcast(json);
  ble::send(json);
}

}  // namespace comms
