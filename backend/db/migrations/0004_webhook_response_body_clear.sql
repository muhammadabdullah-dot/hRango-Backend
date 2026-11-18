-- Webhook deliveries no longer keep the receiver's reply (BE-03): a reply read back through the delivery
-- list let a customer read pages of other systems. Clears what earlier deliveries stored. The column stays
-- so older procedure versions keep working until they are replaced.

UPDATE [core].[webhook_delivery] SET response_body = NULL WHERE response_body IS NOT NULL;
GO
